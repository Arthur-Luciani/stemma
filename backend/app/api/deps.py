from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from app.config import Settings
from app.db.deps import get_db
from app.services.health import HealthService
from app.services.identity import IdentityService
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


def get_session_service(
    db: DbSession, storage: Annotated[Storage, Depends(get_storage)]
) -> SessionService:
    return SessionService(db, storage)


def get_identity_service(db: DbSession) -> IdentityService:
    return IdentityService(db)


def get_mix_service(
    sessions: Annotated[SessionService, Depends(get_session_service)],
) -> MixService:
    return MixService(sessions)


def get_health_service(
    request: Request, settings: Annotated[Settings, Depends(get_app_settings)]
) -> HealthService:
    return HealthService(settings, request.app.state.engine)


SessionServiceDep = Annotated[SessionService, Depends(get_session_service)]
IdentityServiceDep = Annotated[IdentityService, Depends(get_identity_service)]
MixServiceDep = Annotated[MixService, Depends(get_mix_service)]
HealthServiceDep = Annotated[HealthService, Depends(get_health_service)]
