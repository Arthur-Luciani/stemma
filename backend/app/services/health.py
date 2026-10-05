"""Checagens baratas para o `/health` (nada de subprocess aqui)."""

import logging
import shutil

from sqlalchemy import Engine, text

from app import __version__
from app.config import Settings
from app.schemas.health import Check, DbCheck, HealthOut

logger = logging.getLogger(__name__)


class HealthService:
    def __init__(self, settings: Settings, engine: Engine) -> None:
        self.settings = settings
        self.engine = engine

    def check(self) -> HealthOut:
        db = self._check_db()
        return HealthOut(
            status="ok" if db == "ok" else "degraded",
            version=__version__,
            db=db,
            ffmpeg=_binary(self.settings.ffmpeg_bin),
            js_runtime=_binary(self.settings.ytdlp_js_runtime),
            gpu="unknown",
        )

    def _check_db(self) -> DbCheck:
        try:
            with self.engine.connect() as conn:
                conn.execute(text("SELECT 1"))
        except Exception:
            logger.exception("Banco indisponível no /health")
            return "error"
        return "ok"


def _binary(name: str) -> Check:
    return "ok" if shutil.which(name) else "missing"
