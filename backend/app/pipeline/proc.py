"""Execução de subprocessos do pipeline (ADR 0004): timeout, stderr capturado e cancelamento.

O stderr é lido em pedaços e quebrado em `\\n` e `\\r` (barras de progresso do tqdm e do
ffmpeg reescrevem a linha com `\\r`); cada linha vai para o `on_line` e as últimas ficam
guardadas para a mensagem de erro.

O `on_line` roda na thread leitora (só para parsear); o `on_poll` roda na thread do job a
cada volta da espera e é onde se grava progresso no banco.
"""

import collections
import contextlib
import logging
import os
import re
import subprocess
import sys
import threading
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import IO, Protocol

from app.pipeline.queue import CancellableTask, JobCancelledError

logger = logging.getLogger(__name__)

# Linhas finais do stderr guardadas para diagnóstico.
STDERR_TAIL_LINES = 40
_POLL_S = 0.1
_LINE_BREAK = re.compile(rb"[\r\n]+")
# Sem janela de console quando o app roda como serviço no Windows.
_CREATION_FLAGS = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0


class Attachable(Protocol):
    """O pedaço do `JobContext` que o subprocess usa para ser cancelável."""

    @property
    def cancelled(self) -> bool: ...

    def attach(self, task: CancellableTask | None) -> None: ...


class BinaryNotFoundError(Exception):
    def __init__(self, binary: str) -> None:
        super().__init__(binary)
        self.binary = binary


class ProcessTimeoutError(Exception):
    def __init__(self, timeout: float) -> None:
        super().__init__(f"passou de {timeout:.0f} s")
        self.timeout = timeout


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: bytes
    stderr_tail: str

    @property
    def ok(self) -> bool:
        return self.returncode == 0


class _ProcessTask:
    """`CancellableTask` que encerra o processo (e os filhos, no Windows)."""

    def __init__(self, process: "subprocess.Popen[bytes]") -> None:
        self.process = process

    def cancel(self) -> None:
        kill_tree(self.process)


def kill_tree(process: "subprocess.Popen[bytes]") -> None:
    if process.poll() is not None:
        return
    if sys.platform == "win32":
        # `kill()` no Windows não alcança netos; o taskkill /T derruba a árvore toda.
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(process.pid)],
            capture_output=True,
            check=False,
            creationflags=_CREATION_FLAGS,
        )
    if process.poll() is None:
        process.kill()


def run_process(
    cmd: Sequence[str | Path],
    *,
    timeout: float,
    ctx: Attachable | None = None,
    on_line: Callable[[str], None] | None = None,
    on_poll: Callable[[], None] | None = None,
    env: Mapping[str, str] | None = None,
    capture_stdout: bool = False,
) -> ProcessResult:
    """Roda `cmd` até o fim. Não levanta por código de saída (quem chama decide);
    levanta `ProcessTimeoutError`, `BinaryNotFoundError` ou `JobCancelledError`."""
    args = [str(part) for part in cmd]
    logger.debug("Rodando: %s", " ".join(args))
    try:
        process = subprocess.Popen(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE if capture_stdout else subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            env={**os.environ, **env} if env is not None else None,
            creationflags=_CREATION_FLAGS,
        )
    except FileNotFoundError as exc:
        raise BinaryNotFoundError(args[0]) from exc

    tail: collections.deque[str] = collections.deque(maxlen=STDERR_TAIL_LINES)
    stdout_chunks: list[bytes] = []
    readers = [
        threading.Thread(target=_read_lines, args=(process.stderr, tail, on_line), daemon=True)
    ]
    if capture_stdout:
        readers.append(
            threading.Thread(target=_read_all, args=(process.stdout, stdout_chunks), daemon=True)
        )
    for reader in readers:
        reader.start()

    task = _ProcessTask(process)
    if ctx is not None:
        ctx.attach(task)
    deadline = time.monotonic() + timeout
    try:
        while process.poll() is None:
            if ctx is not None and ctx.cancelled:
                kill_tree(process)
                raise JobCancelledError
            if time.monotonic() > deadline:
                kill_tree(process)
                raise ProcessTimeoutError(timeout)
            if on_poll is not None:
                on_poll()
            with contextlib.suppress(subprocess.TimeoutExpired):
                process.wait(_POLL_S)
    finally:
        if ctx is not None:
            ctx.attach(None)
        if process.poll() is None:
            kill_tree(process)
        process.wait()
        for reader in readers:
            reader.join(5)

    if ctx is not None and ctx.cancelled:
        # Morto pelo `task.cancel()` vindo da API.
        raise JobCancelledError
    return ProcessResult(process.returncode, b"".join(stdout_chunks), "\n".join(tail))


def _read_lines(
    stream: IO[bytes] | None,
    tail: collections.deque[str],
    on_line: Callable[[str], None] | None,
) -> None:
    if stream is None:
        return
    pending = b""
    while chunk := stream.read1(4096):  # type: ignore[attr-defined]
        pending += chunk
        parts = _LINE_BREAK.split(pending)
        pending = parts.pop()
        for part in parts:
            _emit(part, tail, on_line)
    if pending:
        _emit(pending, tail, on_line)


def _emit(raw: bytes, tail: collections.deque[str], on_line: Callable[[str], None] | None) -> None:
    line = raw.decode("utf-8", errors="replace").strip()
    if not line:
        return
    tail.append(line)
    if on_line is not None:
        try:
            on_line(line)
        except Exception:  # pragma: no cover - rede de segurança
            # Callback de progresso nunca derruba a leitura (senão o pipe enche e trava).
            logger.exception("Falha ao tratar a saída do subprocess")


def _read_all(stream: IO[bytes] | None, chunks: list[bytes]) -> None:
    if stream is None:
        return
    while chunk := stream.read(65536):
        chunks.append(chunk)
