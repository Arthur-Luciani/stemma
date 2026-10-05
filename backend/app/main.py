import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import __version__
from app.api import artists, health, mix, sessions
from app.api.errors import install_error_handlers
from app.config import Settings, get_settings
from app.db.engine import make_engine, make_sessionmaker
from app.logging_setup import configure_logging
from app.storage import Storage

logger = logging.getLogger(__name__)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    engine = make_engine(settings.database_url)

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        settings.storage_root.mkdir(parents=True, exist_ok=True)
        logger.info("Stemma %s — dados em %s", __version__, settings.storage_root)
        yield
        engine.dispose()

    app = FastAPI(title="Stemma", version=__version__, lifespan=lifespan)
    app.state.settings = settings
    app.state.engine = engine
    app.state.sessionmaker = make_sessionmaker(engine)
    app.state.storage = Storage(settings.storage_root)

    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["*"],
            allow_headers=["*"],
        )
    install_error_handlers(app)
    app.include_router(health.router)
    app.include_router(sessions.router)
    app.include_router(mix.router)
    app.include_router(artists.router)
    return app


app = create_app()
