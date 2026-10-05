"""Checagens baratas para o `/health`. A GPU vem da sonda em segundo plano
(`pipeline/probe.py`); aqui nada roda subprocess."""

import logging
import shutil
from functools import lru_cache

from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import Engine, text
from sqlalchemy.exc import OperationalError
from yt_dlp.version import __version__ as ytdlp_version

from app import __version__
from app.config import BACKEND_DIR, Settings
from app.pipeline.probe import GpuProbe
from app.schemas.health import Check, DbCheck, HealthOut

logger = logging.getLogger(__name__)


class HealthService:
    def __init__(self, settings: Settings, engine: Engine, gpu: GpuProbe) -> None:
        self.settings = settings
        self.engine = engine
        self.gpu = gpu

    def check(self) -> HealthOut:
        db = self._check_db()
        return HealthOut(
            status="ok" if db == "ok" else "degraded",
            version=__version__,
            db=db,
            ffmpeg=_binary(self.settings.ffmpeg_bin),
            js_runtime=_any_binary(self.settings.ytdlp_js_runtime),
            gpu=self.gpu.status,
            ytdlp=ytdlp_version,
        )

    def _check_db(self) -> DbCheck:
        try:
            with self.engine.connect() as conn:
                conn.execute(text("SELECT 1"))
                try:
                    current = conn.execute(text("SELECT version_num FROM alembic_version")).scalar()
                except OperationalError:
                    current = None  # tabela não existe: banco nunca migrado
        except Exception:
            logger.exception("Banco indisponível no /health")
            return "error"
        if current != expected_db_revision():
            logger.warning("Banco na revisão %s; esperado %s", current, expected_db_revision())
            return "outdated"
        return "ok"


@lru_cache
def expected_db_revision() -> str | None:
    """Head das migrations que acompanham este código."""
    return ScriptDirectory.from_config(Config(BACKEND_DIR / "alembic.ini")).get_current_head()


def _binary(name: str) -> Check:
    return "ok" if shutil.which(name) else "missing"


def _any_binary(names: list[str]) -> Check:
    return "ok" if any(shutil.which(name) for name in names) else "missing"
