import sys
import threading

import pytest

from app.pipeline.proc import BinaryNotFoundError, ProcessTimeoutError, run_process
from app.pipeline.queue import CancellableTask, JobCancelledError

PY = sys.executable


class FakeCtx:
    """O pedaço do `JobContext` que o `run_process` usa."""

    def __init__(self) -> None:
        self._cancel = threading.Event()
        self.task: CancellableTask | None = None
        self.attached: list[CancellableTask | None] = []

    @property
    def cancelled(self) -> bool:
        return self._cancel.is_set()

    def attach(self, task: CancellableTask | None) -> None:
        self.task = task
        self.attached.append(task)

    def cancel(self) -> None:
        self._cancel.set()
        if self.task is not None:
            self.task.cancel()


def test_captura_stdout_e_codigo_de_saida() -> None:
    result = run_process(
        [PY, "-c", "import sys; sys.stdout.write('oi'); sys.exit(3)"],
        timeout=10,
        capture_stdout=True,
    )

    assert result.returncode == 3
    assert not result.ok
    assert result.stdout == b"oi"


def test_stderr_em_linhas_com_cr_e_lf() -> None:
    lines: list[str] = []
    script = "import sys; sys.stderr.write('10%|a\\r50%|b\\r100%|c\\nfim\\n')"

    result = run_process([PY, "-c", script], timeout=10, on_line=lines.append)

    assert lines == ["10%|a", "50%|b", "100%|c", "fim"]
    assert result.stderr_tail.endswith("fim")


def test_timeout_mata_o_processo() -> None:
    with pytest.raises(ProcessTimeoutError):
        run_process([PY, "-c", "import time; time.sleep(30)"], timeout=0.5)


def test_binario_inexistente() -> None:
    with pytest.raises(BinaryNotFoundError):
        run_process(["nao-existe-stemma-xyz"], timeout=5)


def test_cancelamento_mata_o_processo_e_solta_o_handle() -> None:
    ctx = FakeCtx()
    timer = threading.Timer(0.5, ctx.cancel)
    timer.start()
    try:
        with pytest.raises(JobCancelledError):
            run_process([PY, "-c", "import time; time.sleep(30)"], timeout=30, ctx=ctx)
    finally:
        timer.cancel()

    assert ctx.attached[0] is not None
    assert ctx.attached[-1] is None


def test_on_poll_roda_na_thread_que_chamou() -> None:
    threads: set[int] = set()

    run_process(
        [PY, "-c", "import time; time.sleep(0.4)"],
        timeout=10,
        on_poll=lambda: threads.add(threading.get_ident()),
    )

    assert threads == {threading.get_ident()}
