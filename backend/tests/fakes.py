"""Dublês para testar a fila sem depender de tempo: o handler só termina quando o teste manda."""

import queue
import threading
import time
from collections.abc import Callable

from app.domain.enums import SessionState
from app.pipeline.queue import JobContext

_OK = object()


def wait_until(predicate: Callable[[], object], timeout: float = 5.0) -> None:
    deadline = time.monotonic() + timeout
    while not predicate():
        if time.monotonic() > deadline:
            raise AssertionError("condição não satisfeita a tempo")
        time.sleep(0.01)


class FakeTask:
    def __init__(self) -> None:
        self.cancelled = threading.Event()

    def cancel(self) -> None:
        self.cancelled.set()


class ControlledHandler:
    """Cada job entra na etapa `stage`, reporta 50% e espera o teste chamar `finish()`
    (sucesso) ou `fail(exc)`. Cancelamento é respeitado, salvo com `ignore_cancel`."""

    def __init__(
        self, stage: SessionState = SessionState.DOWNLOADING, *, ignore_cancel: bool = False
    ) -> None:
        self.stage = stage
        self.ignore_cancel = ignore_cancel
        self.started: queue.Queue[str] = queue.Queue()
        self.tasks: list[FakeTask] = []
        self._gate: queue.Queue[object] = queue.Queue()
        self._lock = threading.Lock()
        self.running = 0
        self.max_running = 0

    def finish(self) -> None:
        self._gate.put(_OK)

    def fail(self, exc: Exception) -> None:
        self._gate.put(exc)

    def next_started(self, timeout: float = 5.0) -> str:
        """Título da sessão do próximo job que começou."""
        return self.started.get(timeout=timeout)

    def run(self, ctx: JobContext) -> None:
        with self._lock:
            self.running += 1
            self.max_running = max(self.max_running, self.running)
        try:
            task = FakeTask()
            self.tasks.append(task)
            ctx.attach(task)
            ctx.set_stage(self.stage)
            ctx.progress(50)
            self.started.put(ctx.session.title)
            while True:
                try:
                    item = self._gate.get(timeout=0.01)
                except queue.Empty:
                    if not self.ignore_cancel:
                        ctx.check_cancelled()
                    continue
                if isinstance(item, Exception):
                    raise item
                return
        finally:
            with self._lock:
                self.running -= 1
