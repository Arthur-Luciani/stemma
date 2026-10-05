"""Tudo que usa ffmpeg (ADR 0004): MP3 dos stems, loudness, peaks e mixdown.

Mixdown (ADR 0010): volume linear `volume/100` e pan com a mesma lei do `StereoPannerNode`
do Web Audio, para o export soar igual ao mixer do navegador.
"""

import array
import json
import logging
import math
import re
import sys
from collections.abc import Collection, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from app.domain.enums import STEMS, ExportFormat, Stem
from app.domain.errors import AppError
from app.pipeline.proc import (
    Attachable,
    BinaryNotFoundError,
    ProcessResult,
    ProcessTimeoutError,
    run_process,
)
from app.schemas.mix import StemMix

logger = logging.getLogger(__name__)

# Peaks: sinal decodificado em mono a esta taxa só para o desenho da waveform.
PEAKS_SAMPLE_RATE = 8000
PEAKS_POINTS = 1600
STEM_MP3_BITRATE = "320k"
EXPORT_MP3_BITRATE = "320k"
SAMPLE_RATE = 44100
# Medição de loudness (mesmos alvos da v1; só o `input_*` é usado).
LOUDNORM_FILTER = "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json"
_LOUDNORM_JSON = re.compile(r"\{\s*\"input_i\"[\s\S]*?\}")


@dataclass(frozen=True)
class Loudness:
    lufs: float | None
    true_peak_db: float | None


@dataclass(frozen=True)
class Peaks:
    duration_s: float
    peaks: list[float]

    def to_json(self) -> dict[str, object]:
        return {"duration_s": self.duration_s, "peaks": self.peaks}


class Ffmpeg:
    def __init__(self, binary: str, timeout: float) -> None:
        self.binary = binary
        self.timeout = timeout

    # --- operações -----------------------------------------------------------

    def to_mp3(self, src: Path, dst: Path, *, ctx: Attachable | None = None) -> None:
        dst.parent.mkdir(parents=True, exist_ok=True)
        self._run(
            ["-i", src, "-vn", "-c:a", "libmp3lame", "-b:a", STEM_MP3_BITRATE, "-y", dst],
            ctx=ctx,
        )

    def measure_loudness(self, src: Path, *, ctx: Attachable | None = None) -> Loudness:
        result = self._run(
            ["-nostats", "-i", src, "-af", LOUDNORM_FILTER, "-f", "null", "-"], ctx=ctx
        )
        return parse_loudnorm(result.stderr_tail)

    def compute_peaks(
        self, src: Path, *, points: int = PEAKS_POINTS, ctx: Attachable | None = None
    ) -> Peaks:
        result = self._run(
            ["-i", src, "-vn", "-ac", "1", "-ar", str(PEAKS_SAMPLE_RATE), "-f", "s16le", "-"],
            ctx=ctx,
            capture_stdout=True,
        )
        samples = array.array("h")
        raw = result.stdout[: len(result.stdout) - len(result.stdout) % 2]
        samples.frombytes(raw)
        if sys.byteorder == "big":
            samples.byteswap()
        return peaks_from_samples(samples, PEAKS_SAMPLE_RATE, points)

    def mixdown(
        self,
        stems: Mapping[Stem, Path],
        levels: Mapping[Stem, StemMix],
        dst: Path,
        fmt: ExportFormat,
        *,
        ctx: Attachable | None = None,
    ) -> None:
        active = active_stems(levels, available=stems.keys())
        if not active:
            raise no_active_stems()
        inputs: list[str | Path] = []
        for stem in active:
            inputs += ["-i", stems[stem]]
        codec = (
            ["-c:a", "pcm_s16le"]
            if fmt is ExportFormat.WAV
            else ["-c:a", "libmp3lame", "-b:a", EXPORT_MP3_BITRATE]
        )
        dst.parent.mkdir(parents=True, exist_ok=True)
        self._run(
            [
                *inputs,
                "-filter_complex",
                build_mix_filter([levels[stem] for stem in active]),
                "-map",
                "[mix]",
                "-ar",
                str(SAMPLE_RATE),
                *codec,
                "-y",
                dst,
            ],
            ctx=ctx,
        )

    # --- interno -------------------------------------------------------------

    def _run(
        self,
        args: Sequence[str | Path],
        *,
        ctx: Attachable | None,
        capture_stdout: bool = False,
    ) -> ProcessResult:
        cmd = [self.binary, "-hide_banner", "-nostdin", *args]
        try:
            result = run_process(cmd, timeout=self.timeout, ctx=ctx, capture_stdout=capture_stdout)
        except BinaryNotFoundError as exc:
            raise AppError(
                "ffmpeg_missing", "FFmpeg não encontrado. Confira o FFMPEG_BIN.", 500
            ) from exc
        except ProcessTimeoutError as exc:
            raise AppError(
                "ffmpeg_timeout", "O processamento do áudio demorou demais e foi interrompido."
            ) from exc
        if not result.ok:
            logger.error("ffmpeg saiu com %d: %s", result.returncode, result.stderr_tail)
            raise AppError("ffmpeg_failed", "Falha ao processar o áudio (ffmpeg).", 500)
        return result


# --- funções puras (testáveis sem ffmpeg) -------------------------------------


def parse_loudnorm(output: str) -> Loudness:
    """Lê o último bloco JSON do `loudnorm` (vem no stderr do ffmpeg)."""
    matches = _LOUDNORM_JSON.findall(output)
    if not matches:
        logger.warning("Saída do loudnorm sem JSON")
        return Loudness(None, None)
    try:
        payload = json.loads(matches[-1])
    except json.JSONDecodeError:
        logger.warning("JSON do loudnorm inválido")
        return Loudness(None, None)
    return Loudness(_finite(payload.get("input_i")), _finite(payload.get("input_tp")))


def peaks_from_samples(samples: Sequence[int], sample_rate: int, points: int) -> Peaks:
    """Máximo absoluto por bucket, normalizado para 0–1 (3 casas)."""
    total = len(samples)
    duration = round(total / sample_rate, 3)
    if total == 0:
        return Peaks(0.0, [])
    count = min(points, total)
    peaks: list[float] = []
    for i in range(count):
        start = i * total // count
        end = max((i + 1) * total // count, start + 1)
        bucket = samples[start:end]
        peak = max(max(bucket), -min(bucket)) / 32768
        peaks.append(round(min(peak, 1.0), 3))
    return Peaks(duration, peaks)


def active_stems(
    levels: Mapping[Stem, StemMix], *, available: Collection[Stem] | None = None
) -> list[Stem]:
    """Stems que soam: com solo, só os solados; mute (ou volume 0) sempre tira, como na v1.
    Um stem solado e mudo não conta como solo."""
    present = [s for s in STEMS if available is None or s in available]
    soloed = {s for s in present if levels[s].solo and not levels[s].mute}
    return [
        s
        for s in present
        if not levels[s].mute and (not soloed or s in soloed) and levels[s].volume > 0
    ]


def pan_gains(pan: float) -> tuple[float, float, float, float]:
    """Matriz do `StereoPannerNode` para entrada estéreo: (LL, LR, RL, RR), em que
    `saída_L = LL·L + LR·R` e `saída_R = RL·L + RR·R`."""
    pan = min(max(pan, -1.0), 1.0)
    if pan <= 0:
        x = (pan + 1) * math.pi / 2
        return (1.0, math.cos(x), 0.0, math.sin(x))
    x = pan * math.pi / 2
    return (math.cos(x), 0.0, math.sin(x), 1.0)


def build_mix_filter(levels: Sequence[StemMix]) -> str:
    """Filtro do mixdown: cada entrada vira estéreo, recebe volume e pan, e tudo é somado."""
    chains: list[str] = []
    for i, level in enumerate(levels):
        ll, lr, rl, rr = pan_gains(level.pan)
        chains.append(
            f"[{i}:a]aformat=channel_layouts=stereo,volume={level.volume / 100:.6f},"
            f"pan=stereo|c0={ll:.6f}*c0+{lr:.6f}*c1|c1={rl:.6f}*c0+{rr:.6f}*c1[s{i}]"
        )
    labels = "".join(f"[s{i}]" for i in range(len(levels)))
    chains.append(f"{labels}amix=inputs={len(levels)}:normalize=0[mix]")
    return ";".join(chains)


def no_active_stems() -> AppError:
    return AppError("no_active_stems", "Nenhum stem soando na mixagem. Tire o mudo ou o solo.", 422)


def _finite(value: object) -> float | None:
    try:
        number = float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    return round(number, 2) if math.isfinite(number) else None
