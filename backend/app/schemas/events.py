"""Eventos do `/ws`: `{"type", "data"}`. Entram no OpenAPI como `LiveEvent` para o frontend."""

import uuid
from typing import Annotated, Literal

from pydantic import BaseModel, Field

from app.domain.enums import EventType
from app.schemas.jobs import JobOut
from app.schemas.sessions import SessionOut


class SessionUpdatedData(BaseModel):
    session: SessionOut


class SessionUpdatedEvent(BaseModel):
    type: Literal[EventType.SESSION_UPDATED]
    data: SessionUpdatedData


class SessionDeletedData(BaseModel):
    id: uuid.UUID


class SessionDeletedEvent(BaseModel):
    type: Literal[EventType.SESSION_DELETED]
    data: SessionDeletedData


class JobUpdatedData(BaseModel):
    job: JobOut


class JobUpdatedEvent(BaseModel):
    type: Literal[EventType.JOB_UPDATED]
    data: JobUpdatedData


LiveEvent = Annotated[
    SessionUpdatedEvent | SessionDeletedEvent | JobUpdatedEvent, Field(discriminator="type")
]
