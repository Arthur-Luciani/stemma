import sys
import textwrap
import threading
from pathlib import Path

import pytest

from app.domain.enums import Stem
from app.domain.errors import AppError
from app.pipeline.queue import JobCancelledError
from app.pipeline.separate import (
    DemucsProgress,
    DemucsSeparator,
    DemucsSettings,
    is_cuda_error,
)
from tests.test_proc import FakeCtx

# `python -m demucs.separate` falso: grava os 4 WAVs, imprime barras do tqdm e se comporta
# conforme o env (FAKE_DEMUCS_FAIL_ON=cuda|all, FAKE_DEMUCS_SLEEP=segundos).
FAKE_DEMUCS = textwrap.dedent(
    """
    import os, sys, time
    from pathlib import Path

    args = sys.argv[1:]
    out = Path(args[args.index("-o") + 1])
    model = args[args.index("-n") + 1]
    device = args[args.index("-d") + 1]
    Path(os.environ["FAKE_DEMUCS_LOG"]).open("a").write(" ".join(args) + "\\n")
    fail_on = os.environ.get("FAKE_DEMUCS_FAIL_ON", "")
    if fail_on == "all" or fail_on == device:
        sys.stderr.write("RuntimeError: CUDA out of memory. Tried to allocate 2 GiB\\n")
        sys.exit(1)
    for pct in (10, 50, 100):
        sys.stderr.write(f"{pct:3d}%|####| {pct}/100 [00:01<00:01]\\r")
        sys.stderr.flush()
    time.sleep(float(os.environ.get("FAKE_DEMUCS_SLEEP", "0")))
    target = out / model
    target.mkdir(parents=True, exist_ok=True)
    for stem in ("vocals", "drums", "bass", "other"):
        (target / f"{stem}.wav").write_bytes(b"RIFF")
    """
)


@pytest.fixture
def fake_demucs(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    package = tmp_path / "fakemods" / "demucs"
    package.mkdir(parents=True)
    (package / "__init__.py").write_text("")
    (package / "separate.py").write_text(FAKE_DEMUCS)
    log = tmp_path / "demucs.log"
    monkeypatch.setenv("PYTHONPATH", str(tmp_path / "fakemods"))
    monkeypatch.setenv("FAKE_DEMUCS_LOG", str(log))
    return log


def make_separator(tmp_path: Path, **overrides: object) -> DemucsSeparator:
    values: dict[str, object] = {
        "model": "htdemucs",
        "device": "auto",
        "segment": 7,
        "overlap": 0.25,
        "shifts": 1,
        "torch_home": tmp_path / "torch",
        "timeout": 30,
        "python": sys.executable,
    }
    values.update(overrides)
    return DemucsSeparator(DemucsSettings(**values))  # type: ignore[arg-type]


def test_comando_montado(tmp_path: Path) -> None:
    separator = make_separator(tmp_path, model="htdemucs_ft", shifts=2, segment=None)

    cmd = separator.command(Path("in.webm"), Path("out"), "cuda")

    assert cmd[:3] == [sys.executable, "-m", "demucs.separate"]
    assert cmd[cmd.index("-n") + 1] == "htdemucs_ft"
    assert cmd[cmd.index("-d") + 1] == "cuda"
    assert cmd[cmd.index("--shifts") + 1] == "2"
    assert cmd[cmd.index("--filename") + 1] == "{stem}.{ext}"
    assert "--segment" not in cmd
    assert cmd[-1] == "in.webm"
    assert separator.bars() == 8
    assert "--segment" in make_separator(tmp_path).command(Path("a"), Path("b"), "cpu")


def test_progresso_das_barras_do_tqdm() -> None:
    progress = DemucsProgress(bars=2)

    progress.feed(" 50%|#####     | 5/10 [00:01<00:01]")
    assert progress.percent == 25
    progress.feed("100%|##########| 10/10")
    assert progress.percent == 50
    progress.feed("  0%|          | 0/10")  # segunda barra
    progress.feed(" 40%|####      | 4/10")
    assert progress.percent == 70
    progress.feed("linha sem barra")
    assert progress.percent == 70


def test_separa_e_reporta_progresso(tmp_path: Path, fake_demucs: Path) -> None:
    separator = make_separator(tmp_path, device="cuda")
    seen: list[float] = []
    source = tmp_path / "source.webm"
    source.write_bytes(b"x")

    result = separator.separate(source, tmp_path / "work", FakeCtx(), seen.append)

    assert result.device == "cuda"
    assert set(result.stems) == set(Stem)
    assert result.stems[Stem.VOCALS].name == "vocals.wav"
    assert result.stems[Stem.VOCALS].parent.name == "htdemucs"


def test_fallback_para_cpu_quando_a_gpu_falha(
    tmp_path: Path, fake_demucs: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("FAKE_DEMUCS_FAIL_ON", "cuda")
    source = tmp_path / "source.webm"
    source.write_bytes(b"x")

    result = make_separator(tmp_path).separate(source, tmp_path / "work", FakeCtx(), print)

    assert result.device == "cpu"
    devices = [line.split(" -d ")[1].split()[0] for line in fake_demucs.read_text().splitlines()]
    assert devices == ["cuda", "cpu"]


def test_falha_sem_fallback_com_device_fixo(
    tmp_path: Path, fake_demucs: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("FAKE_DEMUCS_FAIL_ON", "all")
    source = tmp_path / "source.webm"
    source.write_bytes(b"x")

    with pytest.raises(AppError) as exc:
        make_separator(tmp_path, device="cuda").separate(
            source, tmp_path / "work", FakeCtx(), print
        )

    assert exc.value.code == "separation_failed"
    assert len(fake_demucs.read_text().splitlines()) == 1


def test_cancelamento_mata_o_demucs(
    tmp_path: Path, fake_demucs: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("FAKE_DEMUCS_SLEEP", "30")
    source = tmp_path / "source.webm"
    source.write_bytes(b"x")
    ctx = FakeCtx()
    timer = threading.Timer(1.0, ctx.cancel)
    timer.start()
    try:
        with pytest.raises(JobCancelledError):
            make_separator(tmp_path).separate(source, tmp_path / "work", ctx, print)
    finally:
        timer.cancel()


def test_timeout(tmp_path: Path, fake_demucs: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FAKE_DEMUCS_SLEEP", "30")
    source = tmp_path / "source.webm"
    source.write_bytes(b"x")

    with pytest.raises(AppError) as exc:
        make_separator(tmp_path, timeout=1).separate(source, tmp_path / "work", FakeCtx(), print)

    assert exc.value.code == "separation_timeout"


def test_erro_de_cuda() -> None:
    assert is_cuda_error("RuntimeError: CUDA out of memory")
    assert is_cuda_error("AssertionError: Torch not compiled with CUDA enabled")
    assert not is_cuda_error("Could not load file source.webm")
