"""Sonda da GPU para o `/health`: roda uma vez, em segundo plano, num subprocess (o processo
da API nunca importa o torch). Até terminar, o status é `unknown`."""

import logging
import sys
import threading
from typing import Literal

from app.pipeline.proc import BinaryNotFoundError, ProcessTimeoutError, run_process

logger = logging.getLogger(__name__)

GpuStatus = Literal["ok", "unavailable", "unknown"]
PROBE_TIMEOUT_S = 120.0
_SCRIPT = "import torch; print('cuda' if torch.cuda.is_available() else 'cpu')"


class GpuProbe:
    def __init__(self, command: list[str] | None = None, timeout: float = PROBE_TIMEOUT_S) -> None:
        # Imprime "cuda" se houver GPU utilizável.
        self.command = command or [sys.executable, "-c", _SCRIPT]
        self.timeout = timeout
        self._status: GpuStatus = "unknown"
        self._lock = threading.Lock()
        self._started = False

    @property
    def status(self) -> GpuStatus:
        """Dispara a sonda na primeira consulta e devolve o último resultado."""
        self.start()
        return self._status

    def start(self) -> None:
        with self._lock:
            if self._started:
                return
            self._started = True
        threading.Thread(target=self._run, name="stemma-gpu-probe", daemon=True).start()

    def run_now(self) -> GpuStatus:
        """Roda a sonda nesta thread (usado pela thread de fundo e nos testes)."""
        try:
            result = run_process(self.command, timeout=self.timeout, capture_stdout=True)
        except (BinaryNotFoundError, ProcessTimeoutError):
            logger.warning("Sonda da GPU não respondeu")
            status: GpuStatus = "unavailable"
        else:
            found = result.ok and result.stdout.decode(errors="replace").strip() == "cuda"
            status = "ok" if found else "unavailable"
            if not result.ok:
                logger.warning(
                    "torch indisponível (grupo pipeline instalado?): %s", result.stderr_tail
                )
        self._status = status
        return status

    def _run(self) -> None:
        try:
            status = self.run_now()
            logger.info("GPU: %s", status)
        except Exception:
            logger.exception("Falha na sonda da GPU")
            self._status = "unavailable"
