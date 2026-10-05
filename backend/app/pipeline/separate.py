"""Separação com Demucs via subprocess (ADR 0004): VRAM liberada ao fim de cada job,
cancelamento matando o processo e fallback cuda → cpu quando a GPU falha."""

import logging
import re
import shutil
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from app.domain.enums import STEMS, Stem
from app.domain.errors import AppError
from app.pipeline.proc import Attachable, ProcessTimeoutError, run_process

logger = logging.getLogger(__name__)

# Modelos que são "bags" (vários modelos em sequência, uma barra de progresso cada).
_BAG_SIZES = {"htdemucs_ft": 4, "mdx": 4, "mdx_q": 4, "mdx_extra": 4, "mdx_extra_q": 4}
_PERCENT = re.compile(r"(\d{1,3})%\|")
_CUDA_ERRORS = (
    "cuda",
    "out of memory",
    "cudnn",
    "no kernel image",
    "not compiled with cuda",
)


@dataclass(frozen=True)
class DemucsSettings:
    model: str
    device: str  # auto | cuda | cpu
    segment: int | None
    overlap: float
    shifts: int
    torch_home: Path
    timeout: float
    python: str = sys.executable


@dataclass(frozen=True)
class Separation:
    stems: dict[Stem, Path]
    device: str


class DemucsProgress:
    """Converte as barras do tqdm do Demucs num progresso único, 0–100.

    Cada modelo da bag (e cada shift) abre uma barra nova; quando o percentual volta a cair,
    começou a próxima barra."""

    def __init__(self, bars: int) -> None:
        self.bars = max(bars, 1)
        self.index = 0
        self.last = 0
        self.percent = 0.0

    def feed(self, line: str) -> None:
        matches = _PERCENT.findall(line)
        if not matches:
            return
        value = min(int(matches[-1]), 100)
        if value < self.last:
            self.index = min(self.index + 1, self.bars - 1)
        self.last = value
        self.percent = max(self.percent, 100 * (self.index + value / 100) / self.bars)


class DemucsSeparator:
    def __init__(self, settings: DemucsSettings) -> None:
        self.settings = settings

    def devices(self) -> list[str]:
        if self.settings.device == "auto":
            return ["cuda", "cpu"]
        return [self.settings.device]

    def command(self, source: Path, out_dir: Path, device: str) -> list[str]:
        s = self.settings
        cmd = [
            s.python,
            "-m",
            "demucs.separate",
            "-n",
            s.model,
            "-d",
            device,
            "--overlap",
            str(s.overlap),
            "--shifts",
            str(s.shifts),
            "-o",
            str(out_dir),
            "--filename",
            "{stem}.{ext}",
        ]
        if s.segment is not None:
            cmd += ["--segment", str(s.segment)]
        return [*cmd, str(source)]

    def bars(self) -> int:
        return _BAG_SIZES.get(self.settings.model, 1) * max(self.settings.shifts, 1)

    def separate(
        self,
        source: Path,
        work_dir: Path,
        ctx: Attachable,
        on_progress: Callable[[float], None],
    ) -> Separation:
        """Separa `source` em `work_dir`; `on_progress` recebe 0–100 na thread do job."""
        devices = self.devices()
        for attempt, device in enumerate(devices):
            out_dir = work_dir / "demucs"
            shutil.rmtree(out_dir, ignore_errors=True)
            out_dir.mkdir(parents=True, exist_ok=True)
            progress = DemucsProgress(self.bars())
            logger.info("Demucs (%s, %s) em %s", self.settings.model, device, source.name)
            try:
                result = run_process(
                    self.command(source, out_dir, device),
                    timeout=self.settings.timeout,
                    ctx=ctx,
                    on_line=progress.feed,
                    on_poll=lambda p=progress: on_progress(p.percent),  # type: ignore[misc]
                    env={"TORCH_HOME": str(self.settings.torch_home), "PYTHONIOENCODING": "utf-8"},
                )
            except ProcessTimeoutError as exc:
                raise AppError(
                    "separation_timeout", "A separação demorou demais e foi interrompida."
                ) from exc
            if result.ok:
                return Separation(find_stems(out_dir), device)
            tail = result.stderr_tail
            logger.error("Demucs falhou em %s (código %d): %s", device, result.returncode, tail)
            if "no module named" in tail.lower() and "demucs" in tail.lower():
                raise AppError(
                    "demucs_missing",
                    "O Demucs não está instalado (rode `uv sync --all-groups`).",
                    500,
                )
            has_next = attempt + 1 < len(devices)
            if device == "cuda" and has_next and is_cuda_error(tail):
                logger.warning("GPU falhou; tentando de novo na CPU (mais lento)")
                continue
            break
        raise AppError("separation_failed", "A separação dos stems falhou.", 500)


def is_cuda_error(stderr: str) -> bool:
    lower = stderr.lower()
    return any(key in lower for key in _CUDA_ERRORS)


def find_stems(out_dir: Path) -> dict[Stem, Path]:
    """Os 4 WAVs gerados (o Demucs põe tudo em `out/<modelo>/`)."""
    stems: dict[Stem, Path] = {}
    for stem in STEMS:
        found = sorted(out_dir.rglob(f"{stem.value}.wav"), key=lambda f: f.stat().st_mtime)
        if not found:
            raise AppError(
                "separation_failed", f"O Demucs não gerou o stem {stem.label.lower()}.", 500
            )
        stems[stem] = found[-1]
    return stems
