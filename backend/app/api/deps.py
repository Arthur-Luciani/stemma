from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from app.config import Settings
from app.db.deps import get_db
from app.pipeline.queue import JobRunner
from app.services.events import EventBus, EventPublisher
from app.services.health import HealthService
from app.services.identity import IdentityService
from app.services.jobs import JobService
from app.services.mix import MixService
from app.services.sessions import SessionService
from app.storage import Storage

DbSession = Annotated[Session, Depends(get_db)]


def get_app_settings(request: Request) -> Settings:
    settings: Settings = request.app.state.settings
    return settings


def get_storage(request: Request) -> Storage:
    storage: Storage = request.app.state.storage
    return storage


def get_event_bus(request: Request) -> EventBus:
    bus: EventBus = request.app.state.event_bus
    return bus


def get_job_runner(request: Request) -> JobRunner:
    runner: JobRunner = request.app.state.job_runner
    return runner


def get_event_publisher(
    db: DbSession, bus: Annotated[EventBus, Depends(get_event_bus)]
) -> EventPublisher:
    return EventPublisher(db, bus)


def get_session_service(
    db: DbSession,
    storage: Annotated[Storage, Depends(get_storage)],
    events: Annotated[EventPublisher, Depends(get_event_publisher)],
) -> SessionService:
    return SessionService(db, storage, events)


def get_identity_service(db: DbSession) -> IdentityService:
    return IdentityService(db)


def get_mix_service(
    sessions: Annotated[SessionService, Depends(get_session_service)],
) -> MixService:
    return MixService(sessions)


def get_job_service(
    sessions: Annotated[SessionService, Depends(get_session_service)],
    runner: Annotated[JobRunner, Depends(get_job_runner)],
) -> JobService:
    return JobService(sessions.db, sessions, sessions.events, runner)


def get_health_service(
    request: Request, settings: Annotated[Settings, Depends(get_app_settings)]
) -> HealthService:
    return HealthService(settings, request.app.state.engine)


SessionServiceDep = Annotated[SessionService, Depends(get_session_service)]
IdentityServiceDep = Annotated[IdentityService, Depends(get_identity_service)]
MixServiceDep = Annotated[MixService, Depends(get_mix_service)]
JobServiceDep = Annotated[JobService, Depends(get_job_service)]
HealthServiceDep = Annotated[HealthService, Depends(get_health_service)]
