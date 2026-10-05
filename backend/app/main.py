import logging
from collections.abc import AsyncIterator, Mapping
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import __version__
from app.api import artists, events, health, jobs, mix, sessions
from app.api.errors import install_error_handlers
from app.config import Settings, get_settings
from app.db.engine import make_engine, make_sessionmaker
from app.domain.enums import JobKind
from app.logging_setup import configure_logging
from app.pipeline.fake import FakeProcessHandler
from app.pipeline.queue import JobHandler, JobRunner
from app.services.events import EventBus
from app.storage import Storage

logger = logging.getLogger(__name__)


def default_job_handlers(settings: Settings) -> dict[JobKind, JobHandler]:
    # Os handlers reais entram na F2b; sem eles, o job falha com `pipeline_unavailable`.
    if settings.stemma_fake_pipeline:
        return {JobKind.PROCESS: FakeProcessHandler(settings.fake_pipeline_seconds)}
    return {}


def create_app(
    settings: Settings | None = None,
    *,
    job_handlers: Mapping[JobKind, JobHandler] | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    engine = make_engine(settings.database_url)
    sessionmaker = make_sessionmaker(engine)
    event_bus = EventBus()
    handlers = default_job_handlers(settings) if job_handlers is None else job_handlers
    job_runner = JobRunner(
        sessionmaker, event_bus, handlers, max_attempts=settings.job_max_attempts
    )

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        settings.storage_root.mkdir(parents=True, exist_ok=True)
        logger.info("Stemma %s — dados em %s", __version__, settings.storage_root)
        job_runner.start()
        try:
            yield
        finally:
            job_runner.stop()
            engine.dispose()

    app = FastAPI(title="Stemma", version=__version__, lifespan=lifespan)
    app.state.settings = settings
    app.state.engine = engine
    app.state.sessionmaker = sessionmaker
    app.state.event_bus = event_bus
    app.state.job_runner = job_runner
    app.state.storage = Storage(settings.storage_root)

    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["*"],
            allow_headers=["*"],
        )
    install_error_handlers(app)
    events.install_event_schemas(app)
    app.include_router(health.router)
    app.include_router(sessions.router)
    app.include_router(mix.router)
    app.include_router(artists.router)
    app.include_router(jobs.router)
    app.include_router(events.router)
    return app


app = create_app()
