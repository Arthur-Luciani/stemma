import json
from pathlib import Path

import pytest

from app.domain.enums import ExportFormat, Stem
from app.domain.errors import AppError
from app.pipeline.audio import (
    Ffmpeg,
    active_stems,
    build_mix_filter,
    pan_gains,
    parse_loudnorm,
    peaks_from_samples,
)
from app.schemas.mix import StemMix
from tests.audio_fixtures import FFMPEG, channel_peaks, needs_ffmpeg, sine_wav

LOUDNORM_OUTPUT = """
[Parsed_loudnorm_0 @ 000001]
{
    "input_i" : "-16.42",
    "input_tp" : "-0.97",
    "input_lra" : "5.10",
    "input_thresh" : "-26.60",
    "output_i" : "-14.01",
    "output_tp" : "-1.50",
    "normalization_type" : "dynamic",
    "target_offset" : "0.01"
}
"""


def levels(**overrides: StemMix) -> dict[Stem, StemMix]:
    base = {stem: StemMix() for stem in Stem}
    base.update({Stem(k): v for k, v in overrides.items()})
    return base


@pytest.fixture
def ffmpeg() -> Ffmpeg:
    return Ffmpeg(FFMPEG or "ffmpeg", timeout=60)


# --- puras -------------------------------------------------------------------


def test_parse_loudnorm() -> None:
    result = parse_loudnorm(LOUDNORM_OUTPUT)

    assert result.lufs == -16.42
    assert result.true_peak_db == -0.97


def test_parse_loudnorm_silencio_e_saida_sem_json() -> None:
    silent = LOUDNORM_OUTPUT.replace('"-16.42"', '"-inf"').replace('"-0.97"', '"-inf"')

    assert parse_loudnorm(silent).lufs is None
    assert parse_loudnorm(silent).true_peak_db is None
    assert parse_loudnorm("nada aqui").lufs is None


def test_peaks_por_bucket() -> None:
    samples = [0, 16384, -32768, 100] * 4  # 16 amostras

    peaks = peaks_from_samples(samples, sample_rate=8, points=4)

    assert peaks.duration_s == 2.0
    assert peaks.peaks == [1.0, 1.0, 1.0, 1.0]
    assert peaks_from_samples([], 8000, 100).peaks == []
    # Menos amostras que pontos: um ponto por amostra.
    assert peaks_from_samples([16384, 0], 8000, 100).peaks == [0.5, 0.0]


def test_pan_igual_ao_stereo_panner_do_web_audio() -> None:
    assert pan_gains(0) == pytest.approx((1, 0, 0, 1), abs=1e-9)
    assert pan_gains(-1) == pytest.approx((1, 1, 0, 0), abs=1e-9)
    assert pan_gains(1) == pytest.approx((0, 0, 1, 1), abs=1e-9)
    ll, lr, rl, rr = pan_gains(-0.5)
    assert (ll, rl) == (1, 0)
    assert lr**2 + rr**2 == pytest.approx(1)  # equal-power


def test_stems_ativos_respeitam_mute_e_solo() -> None:
    assert active_stems(levels()) == list(Stem)
    assert active_stems(levels(vocals=StemMix(mute=True))) == [Stem.DRUMS, Stem.BASS, Stem.OTHER]
    assert active_stems(levels(bass=StemMix(solo=True), drums=StemMix(solo=True))) == [
        Stem.DRUMS,
        Stem.BASS,
    ]
    # Mute vence o solo, e volume 0 não entra.
    assert active_stems(levels(bass=StemMix(solo=True, mute=True), other=StemMix(volume=0))) == [
        Stem.VOCALS,
        Stem.DRUMS,
    ]
    assert active_stems(levels(), available={Stem.VOCALS}) == [Stem.VOCALS]


def test_filtro_do_mix() -> None:
    graph = build_mix_filter([StemMix(volume=50), StemMix(pan=-1)])

    assert "[0:a]aformat=channel_layouts=stereo,volume=0.500000," in graph
    assert "c1=0.000000*c0+0.000000*c1[s1]" in graph
    assert graph.endswith("[s0][s1]amix=inputs=2:normalize=0[mix]")


# --- com ffmpeg real ---------------------------------------------------------


@needs_ffmpeg
def test_mp3_peaks_e_loudness(ffmpeg: Ffmpeg, tmp_path: Path) -> None:
    wav = sine_wav(tmp_path / "seno.wav", seconds=3, volume=0.5)

    ffmpeg.to_mp3(wav, tmp_path / "out" / "seno.mp3")
    peaks = ffmpeg.compute_peaks(wav, points=300)
    loudness = ffmpeg.measure_loudness(wav)

    assert (tmp_path / "out" / "seno.mp3").stat().st_size > 1000
    assert peaks.duration_s == pytest.approx(3, abs=0.01)
    assert len(peaks.peaks) == 300
    assert max(peaks.peaks) == pytest.approx(0.5, abs=0.02)
    assert loudness.lufs is not None
    assert -12 < loudness.lufs < -3
    assert loudness.true_peak_db == pytest.approx(-6, abs=0.6)
    json.dumps(peaks.to_json())


@needs_ffmpeg
def test_mixdown_volume_e_pan(ffmpeg: Ffmpeg, tmp_path: Path) -> None:
    stems = {
        Stem.VOCALS: sine_wav(tmp_path / "v.wav", freq=440, volume=0.4),
        Stem.DRUMS: sine_wav(tmp_path / "d.wav", freq=880, volume=0.4),
    }
    out = tmp_path / "mix.wav"

    # Bateria muda; voz toda à esquerda (o direito fica em silêncio).
    ffmpeg.mixdown(
        stems,
        levels(vocals=StemMix(pan=-1), drums=StemMix(mute=True)),
        out,
        ExportFormat.WAV,
    )

    left, right = channel_peaks(out)
    assert left == pytest.approx(0.8, abs=0.03)  # L + R somados no lado esquerdo
    assert right < 0.001


@needs_ffmpeg
def test_mixdown_soma_e_mp3_320(ffmpeg: Ffmpeg, tmp_path: Path) -> None:
    stems = {
        Stem.VOCALS: sine_wav(tmp_path / "v.wav", freq=440, volume=0.25),
        Stem.BASS: sine_wav(tmp_path / "b.wav", freq=440, volume=0.25),
    }
    wav, mp3 = tmp_path / "mix.wav", tmp_path / "mix.mp3"

    ffmpeg.mixdown(stems, levels(bass=StemMix(volume=50)), wav, ExportFormat.WAV)
    ffmpeg.mixdown(stems, levels(), mp3, ExportFormat.MP3)

    # Mesma fase: 0,25 + 0,25·0,5 = 0,375.
    assert channel_peaks(wav)[0] == pytest.approx(0.375, abs=0.02)
    # 2 s a 320 kbps ≈ 80 kB.
    assert 70_000 < mp3.stat().st_size < 95_000


@needs_ffmpeg
def test_mixdown_sem_stem_ativo(ffmpeg: Ffmpeg, tmp_path: Path) -> None:
    stems = {Stem.VOCALS: sine_wav(tmp_path / "v.wav")}

    with pytest.raises(AppError) as exc:
        ffmpeg.mixdown(
            stems, levels(vocals=StemMix(mute=True)), tmp_path / "x.wav", ExportFormat.WAV
        )

    assert exc.value.code == "no_active_stems"


@needs_ffmpeg
def test_erro_do_ffmpeg_vira_app_error(ffmpeg: Ffmpeg, tmp_path: Path) -> None:
    with pytest.raises(AppError) as exc:
        ffmpeg.to_mp3(tmp_path / "nao-existe.wav", tmp_path / "x.mp3")

    assert exc.value.code == "ffmpeg_failed"


def test_ffmpeg_ausente(tmp_path: Path) -> None:
    with pytest.raises(AppError) as exc:
        Ffmpeg("ffmpeg-que-nao-existe", timeout=5).to_mp3(tmp_path / "a.wav", tmp_path / "b.mp3")

    assert exc.value.code == "ffmpeg_missing"
