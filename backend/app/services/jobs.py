"""Fila de jobs vista pela API: enfileirar, listar, cancelar e descartar.

A execução fica com o `JobRunner` (pipeline/queue.py); aqui só se grava no banco, se avisa
o runner e se publicam os eventos.
"""

import logging
import uuid

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.db.models import JobModel, SessionModel
from app.db.types import utcnow
from app.domain.enums import (
    ACTIVE_JOB_STATES,
    DISMISSABLE_JOB_STATES,
    JobKind,
    JobState,
    SessionState,
)
from app.domain.errors import ConflictError, job_not_found
from app.pipeline.eta import QueueEstimator
from app.pipeline.queue import JobRunner
from app.schemas.jobs import JobOut
from app.services.events import EventPublisher, build_job_out
from app.services.sessions import SessionService

logger = logging.getLogger(__name__)

# Quantos jobs encerrados (prontos/falhos, não descartados) aparecem no dock.
FINISHED_LIMIT = 10
# Estados em que a sessão pode ser reprocessada.
REPROCESSABLE_STATES = (SessionState.READY, SessionState.FAILED)


class JobService:
    def __init__(
        self,
        db: Session,
        sessions: SessionService,
        events: EventPublisher,
        runner: JobRunner,
    ) -> None:
        self.db = db
        self.sessions = sessions
        self.events = events
        self.runner = runner

    # --- leitura -----------------------------------------------------------

    def list(self) -> list[JobOut]:
        """Em execução, depois a fila por chegada, depois os encerrados mais recentes."""
        active = self.db.execute(
            select(JobModel, SessionModel)
            .join(SessionModel, SessionModel.id == JobModel.session_id)
            .where(JobModel.state.in_(ACTIVE_JOB_STATES))
            .order_by(JobModel.created_at, JobModel.id)
        ).all()
        finished = self.db.execute(
            select(JobModel, SessionModel)
            .join(SessionModel, SessionModel.id == JobModel.session_id)
            .where(JobModel.state.in_(DISMISSABLE_JOB_STATES), JobModel.dismissed_at.is_(None))
            .order_by(JobModel.finished_at.desc(), JobModel.id)
            .limit(FINISHED_LIMIT)
        ).all()
        running = [r for r in active if r[0].state is JobState.RUNNING]
        queued = [r for r in active if r[0].state is JobState.QUEUED]
        estimates = QueueEstimator(self.db).estimate()
        return [
            build_job_out(job, session, estimates.get(job.id))
            for job, session in (*running, *queued, *finished)
        ]

    def get(self, job_id: uuid.UUID) -> JobOut:
        row = self.db.execute(
            select(JobModel, SessionModel)
            .join(SessionModel, SessionModel.id == JobModel.session_id)
            .where(JobModel.id == job_id)
        ).first()
        if row is None:
            raise job_not_found()
        job, session = row
        return build_job_out(job, session, QueueEstimator(self.db).estimate().get(job.id))

    # --- escrita -----------------------------------------------------------

    def process(self, session_id: uuid.UUID) -> JobOut:
        """Confirma o rascunho e o põe na fila."""
        session = self.sessions.get(session_id)
        if session.state is not SessionState.DRAFT:
            raise ConflictError(
                "session_not_draft", "Esta sessão já foi enviada para processamento."
            )
        return self._enqueue(session_id, from_states=(SessionState.DRAFT,))

    def reprocess(self, session_id: uuid.UUID) -> JobOut:
        """Processa de novo uma sessão pronta ou que falhou. Recusa se já houver job ativo."""
        session = self.sessions.get(session_id)
        if session.state is SessionState.DRAFT:
            raise ConflictError(
                "session_not_processed",
                "Esta sessão ainda é um rascunho. Use Separar para processá-la.",
            )
        if session.state not in REPROCESSABLE_STATES or self.sessions.has_active_job(session_id):
            raise _session_busy()
        return self._enqueue(session_id, from_states=REPROCESSABLE_STATES)

    def cancel(self, job_id: uuid.UUID) -> None:
        job = self._get_model(job_id)
        now = utcnow()
        cancelled = self.db.scalar(
            update(JobModel)
            .where(JobModel.id == job_id, JobModel.state.in_(ACTIVE_JOB_STATES))
            .values(state=JobState.CANCELLED, finished_at=now)
            .returning(JobModel.id)
        )
        if cancelled is None:
            raise ConflictError("job_not_active", "Este job já terminou.")
        if job.kind is JobKind.PROCESS:
            self.db.execute(
                update(SessionModel)
                .where(SessionModel.id == job.session_id)
                .values(
                    state=SessionState.FAILED,
                    progress=0.0,
                    error_code="cancelled",
                    error_message="Processamento cancelado.",
                )
            )
        self.db.commit()
        self.runner.cancel(job_id)
        logger.info("Job %s cancelado", job_id)
        if job.kind is JobKind.PROCESS:
            self.events.session_updated(job.session_id)
        self.events.jobs_changed(job_id)

    def discard(self, job_id: uuid.UUID) -> None:
        """Tira do dock um job encerrado (pronto ou falho). A sessão não muda."""
        self._get_model(job_id)
        dismissed = self.db.scalar(
            update(JobModel)
            .where(
                JobModel.id == job_id,
                JobModel.state.in_(DISMISSABLE_JOB_STATES),
                JobModel.dismissed_at.is_(None),
            )
            .values(dismissed_at=utcnow())
            .returning(JobModel.id)
        )
        if dismissed is None:
            raise ConflictError(
                "job_not_dismissable", "Só dá para descartar um job pronto ou que falhou."
            )
        self.db.commit()

    # --- internos ----------------------------------------------------------

    def _enqueue(self, session_id: uuid.UUID, *, from_states: tuple[SessionState, ...]) -> JobOut:
        # Condicional no estado: duas chamadas simultâneas não criam dois jobs.
        moved = self.db.scalar(
            update(SessionModel)
            .where(SessionModel.id == session_id, SessionModel.state.in_(from_states))
            .values(state=SessionState.QUEUED, progress=0.0, error_code=None, error_message=None)
            .returning(SessionModel.id)
        )
        if moved is None:
            self.db.rollback()
            raise _session_busy()
        # Jobs encerrados anteriores desta sessão saem do dock.
        self.db.execute(
            update(JobModel)
            .where(
                JobModel.session_id == session_id,
                JobModel.state.in_(DISMISSABLE_JOB_STATES),
                JobModel.dismissed_at.is_(None),
            )
            .values(dismissed_at=utcnow())
        )
        job = JobModel(kind=JobKind.PROCESS, session_id=session_id, state=JobState.QUEUED)
        self.db.add(job)
        self.db.flush()
        self.sessions.log_event(session_id, "queued", {"job_id": str(job.id)})
        self.db.commit()
        self.runner.wake()
        logger.info("Sessão %s na fila (job %s)", session_id, job.id)
        self.events.session_updated(session_id)
        self.events.jobs_changed(job.id)
        return self.get(job.id)

    def _get_model(self, job_id: uuid.UUID) -> JobModel:
        job = self.db.get(JobModel, job_id)
        if job is None:
            raise job_not_found()
        return job


def _session_busy() -> ConflictError:
    return ConflictError("session_busy", "Esta sessão já está na fila ou sendo processada.")
