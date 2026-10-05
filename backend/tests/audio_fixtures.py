"""Áudio sintético para os testes (gerado com o ffmpeg do sistema)."""

import array
import shutil
import subprocess
from pathlib import Path

import pytest

FFMPEG = shutil.which("ffmpeg")
needs_ffmpeg = pytest.mark.skipif(FFMPEG is None, reason="ffmpeg não instalado")


def sine_wav(
    path: Path,
    *,
    seconds: float = 2.0,
    freq: int = 440,
    volume: float = 0.5,
    channels: int = 2,
) -> Path:
    """Seno com a amplitude de pico dada (0–1), estéreo por padrão."""
    assert FFMPEG is not None
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            FFMPEG,
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            f"sine=frequency={freq}:sample_rate=44100:duration={seconds}",
            # O `sine` do lavfi sai com pico 1/8; o `pan` duplica sem a atenuação do `-ac 2`.
            "-af",
            f"volume={volume * 8:.4f}" + (",pan=stereo|c0=c0|c1=c0" if channels == 2 else ""),
            "-y",
            str(path),
        ],
        check=True,
    )
    return path


def channel_peaks(path: Path) -> tuple[float, float]:
    """Pico absoluto (0–1) dos canais esquerdo e direito."""
    assert FFMPEG is not None
    raw = subprocess.run(
        [FFMPEG, "-hide_banner", "-loglevel", "error", "-i", str(path), "-f", "s16le", "-"],
        check=True,
        capture_output=True,
    ).stdout
    samples = array.array("h")
    samples.frombytes(raw[: len(raw) - len(raw) % 4])
    left, right = samples[0::2], samples[1::2]
    return max(map(abs, left)) / 32768, max(map(abs, right)) / 32768
