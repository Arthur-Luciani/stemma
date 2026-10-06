import logging
from collections.abc import AsyncIterator, Mapping
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import __version__
from app.api import (
    artists,
    events,
    exports,
    health,
    jobs,
    media,
    mix,
    search,
    sessions,
    system,
)
from app.api.errors import install_error_handlers
from app.config import Settings, get_settings
from app.db.engine import make_engine, make_sessionmaker
from app.domain.enums import JobKind
from app.logging_setup import configure_logging
from app.pipeline.audio import Ffmpeg
from app.pipeline.download import YtDlpClient
from app.pipeline.fake import FakeProcessHandler
from app.pipeline.handlers import ExportHandler, ProcessHandler
from app.pipeline.probe import GpuProbe
from app.pipeline.queue import JobHandler, JobRunner
from app.pipeline.separate import DemucsSeparator, DemucsSettings
from app.pipeline.updater import GitHubReleases, UpdateTask
from app.services.events import EventBus
from app.spa import install_spa
from app.storage import Storage

logger = logging.getLogger(__name__)


def default_job_handlers(settings: Settings, storage: Storage) -> dict[JobKind, JobHandler]:
    ffmpeg = Ffmpeg(settings.ffmpeg_bin, settings.ffmpeg_timeout_s)
    export = ExportHandler(storage, ffmpeg)
    if settings.stemma_fake_pipeline:
        return {
            JobKind.PROCESS: FakeProcessHandler(settings.fake_pipeline_seconds),
            JobKind.EXPORT: export,
        }
    assert settings.torch_home is not None  # preenchido pelo validador do Settings
    process = ProcessHandler(
        storage,
        YtDlpClient(
            js_runtimes=settings.ytdlp_js_runtime,
            cookie_file=settings.ytdlp_cookie_file,
            timeout=settings.download_timeout_s,
        ),
        DemucsSeparator(
            DemucsSettings(
                model=settings.separation_model,
                device=settings.demucs_device,
                segment=settings.demucs_segment,
                overlap=settings.demucs_overlap,
                shifts=settings.demucs_shifts,
                torch_home=settings.torch_home,
                timeout=settings.separation_timeout_s,
            )
        ),
        ffmpeg,
    )
    return {JobKind.PROCESS: process, JobKind.EXPORT: export}


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
    storage = Storage(settings.storage_root)
    gpu_probe = GpuProbe()
    handlers = default_job_handlers(settings, storage) if job_handlers is None else job_handlers
    job_runner = JobRunner(
        sessionmaker, event_bus, handlers, max_attempts=settings.job_max_attempts
    )

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        settings.storage_root.mkdir(parents=True, exist_ok=True)
        logger.info("Stemma %s — dados em %s", __version__, settings.storage_root)
        gpu_probe.start()
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
    app.state.storage = storage
    app.state.gpu_probe = gpu_probe
    app.state.releases = GitHubReleases(settings.update_repo, ttl_s=settings.update_check_ttl_s)
    app.state.update_task = UpdateTask(settings.schtasks_bin, settings.update_task)

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
    app.include_router(search.router)
    app.include_router(exports.router)
    app.include_router(media.router)
    app.include_router(system.router)
    app.include_router(events.router)
    if settings.serve_frontend_dir is not None:
        install_spa(app, settings.serve_frontend_dir)
    return app


app = create_app()
