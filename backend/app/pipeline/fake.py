"""Pipeline falso (`STEMMA_FAKE_PIPELINE=1`): simula download e separação com progresso,
sem yt-dlp/Demucs. Serve para desenvolver o frontend e para testes.

Título com `[falha]` faz o job falhar no meio da separação.
"""

from app.domain.enums import SessionState
from app.domain.errors import AppError
from app.pipeline.queue import JobContext

FAIL_MARKER = "[falha]"
TICK_S = 0.2
# Fração do tempo total gasta em cada etapa.
_STAGES = ((SessionState.DOWNLOADING, 0.3), (SessionState.SEPARATING, 0.7))


class FakeProcessHandler:
    def __init__(self, total_seconds: float, tick_s: float = TICK_S) -> None:
        self.total_seconds = total_seconds
        self.tick_s = tick_s

    def run(self, ctx: JobContext) -> None:
        fail = FAIL_MARKER in ctx.session.title.casefold()
        for stage, share in _STAGES:
            ctx.set_stage(stage)
            steps = max(1, round(self.total_seconds * share / self.tick_s))
            for step in range(1, steps + 1):
                ctx.sleep(self.total_seconds * share / steps)
                if fail and stage is SessionState.SEPARATING and step * 2 >= steps:
                    raise AppError("fake_failure", "Falha simulada pelo pipeline falso.")
                ctx.progress(100 * step / steps)
