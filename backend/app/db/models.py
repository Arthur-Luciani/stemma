"""Modelos ORM. Mudou algo aqui → nova migration Alembic (o teste de drift acusa)."""

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import JSON, Enum, ForeignKey, Index, MetaData, String, Text, Uuid
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.db.types import UTCDateTime, utcnow
from app.domain.enums import (
    ExportFormat,
    ExportState,
    JobKind,
    JobState,
    MixPreset,
    SessionState,
)

NAMING_CONVENTION = {
    "ix": "ix_%(table_name)s_%(column_0_N_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


def _enum[E: StrEnum](enum: type[E]) -> Enum:
    # Guarda o valor (`"ready"`), não o nome (`"READY"`); sem CHECK para facilitar migrations.
    return Enum(
        enum,
        native_enum=False,
        create_constraint=False,
        length=16,
        values_callable=lambda members: [m.value for m in members],
    )


class SessionModel(Base):
    __tablename__ = "sessions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    code: Mapped[str] = mapped_column(String(16), unique=True)
    source_url: Mapped[str] = mapped_column(Text)
    source_title: Mapped[str | None] = mapped_column(Text)
    source_channel: Mapped[str | None] = mapped_column(Text)
    thumbnail_url: Mapped[str | None] = mapped_column(Text)
    artist: Mapped[str] = mapped_column(String(200))
    title: Mapped[str] = mapped_column(String(200))
    # Chaves normalizadas (sem acento/caixa) para autocomplete e busca.
    artist_key: Mapped[str] = mapped_column(String(200), index=True)
    search_key: Mapped[str] = mapped_column(Text)
    duration_s: Mapped[float | None]
    state: Mapped[SessionState] = mapped_column(
        _enum(SessionState), default=SessionState.DRAFT, index=True
    )
    progress: Mapped[float] = mapped_column(default=0.0)
    error_code: Mapped[str | None] = mapped_column(String(64))
    error_message: Mapped[str | None] = mapped_column(Text)
    # {stem: path relativo ao STORAGE_ROOT}
    stems: Mapped[dict[str, str] | None] = mapped_column(JSON)
    # {"lufs": float | None, "true_peak_db": float | None}
    metrics: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)
    processed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class CounterModel(Base):
    """Sequências nomeadas (ex.: `session_code` → ST-###). Nunca reaproveita valores."""

    __tablename__ = "counters"

    name: Mapped[str] = mapped_column(String(32), primary_key=True)
    value: Mapped[int]


class ExportModel(Base):
    __tablename__ = "exports"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sessions.id", ondelete="CASCADE"), index=True
    )
    format: Mapped[ExportFormat] = mapped_column(_enum(ExportFormat))
    preset: Mapped[MixPreset | None] = mapped_column(_enum(MixPreset))
    # Snapshot dos níveis usados: {stem: {volume, pan, mute, solo}}
    levels: Mapped[dict[str, Any]] = mapped_column(JSON)
    state: Mapped[ExportState] = mapped_column(_enum(ExportState), default=ExportState.QUEUED)
    progress: Mapped[float] = mapped_column(default=0.0)
    path: Mapped[str | None] = mapped_column(Text)
    size_bytes: Mapped[int | None]
    lufs: Mapped[float | None]
    error_code: Mapped[str | None] = mapped_column(String(64))
    error_message: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)
    finished_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class JobModel(Base):
    """Fila persistente (ADR 0003). Usada a partir da F2a."""

    __tablename__ = "jobs"
    __table_args__ = (Index(None, "state", "created_at"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    kind: Mapped[JobKind] = mapped_column(_enum(JobKind))
    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sessions.id", ondelete="CASCADE"), index=True
    )
    export_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("exports.id", ondelete="CASCADE")
    )
    state: Mapped[JobState] = mapped_column(_enum(JobState), default=JobState.QUEUED)
    # Etapa atual (process: downloading/separating) e progresso dela, 0–100.
    stage: Mapped[SessionState | None] = mapped_column(_enum(SessionState))
    progress: Mapped[float] = mapped_column(default=0.0)
    attempt: Mapped[int] = mapped_column(default=0)
    error_code: Mapped[str | None] = mapped_column(String(64))
    error_message: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)
    started_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    stage_started_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    # {etapa: segundos} das etapas concluídas; base do ETA (média móvel).
    stage_durations: Mapped[dict[str, float] | None] = mapped_column(JSON)
    finished_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    # Job falho que o usuário tirou do dock (a sessão continua "Falhou").
    dismissed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class SessionEventModel(Base):
    """Log append-only do que aconteceu com cada sessão."""

    __tablename__ = "session_events"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sessions.id", ondelete="CASCADE"), index=True
    )
    type: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class MixStateModel(Base):
    __tablename__ = "mix_states"

    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sessions.id", ondelete="CASCADE"), primary_key=True
    )
    # {stem: {volume: 0–100, pan: -1..1, mute: bool, solo: bool}}
    stems: Mapped[dict[str, Any]] = mapped_column(JSON)
    preset: Mapped[MixPreset] = mapped_column(_enum(MixPreset), default=MixPreset.ORIGINAL)
    loop_a_s: Mapped[float | None]
    loop_b_s: Mapped[float | None]
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)
