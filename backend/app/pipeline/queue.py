"""Fila persistente de jobs (ADR 0003): o estado vive na tabela `jobs`; aqui só se executa.

Cada worker é uma thread com um conjunto de kinds; o de GPU (`process`) roda um job por vez.
Toda escrita do runner é condicional a `state = 'running'`: se a API cancelou o job no meio,
nada do runner sobrescreve o cancelamento.
"""

import logging
import threading
import time
import uuid
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol

from sqlalchemy import select, update
from sqlalchemy.orm import Session, sessionmaker

from app.db.models import JobModel, SessionModel
from app.db.types import utcnow
from app.domain.enums import JobKind, JobState, SessionState
from app.domain.errors import AppError
from app.pipeline.eta import RUN_STAGE
from app.services.events import EventBus, EventPublisher

logger = logging.getLogger(__name__)

# Workers: nome → kinds que ele executa (um job por vez em cada worker).
LANES: dict[str, tuple[JobKind, ...]] = {
    "gpu": (JobKind.PROCESS,),
    "light": (JobKind.EXPORT,),
}
# Rede de segurança caso um aviso de "job novo" se perca.
POLL_INTERVAL_S = 1.0
# Intervalo mínimo entre gravações de progresso da mesma etapa.
PROGRESS_INTERVAL_S = 0.5
STOP_TIMEOUT_S = 10.0


class CancellableTask(Protocol):
    """Algo em execução que pode ser interrompido (na F2b, um subprocess)."""

    def cancel(self) -> None: ...


class JobCancelledError(Exception):
    """O job foi cancelado (pela API ou pelo desligamento do servidor)."""


@dataclass(frozen=True)
class SessionInfo:
    """Dados da sessão de que o handler precisa, lidos ao começar o job."""

    id: uuid.UUID
    code: str
    source_url: str
    artist: str
    title: str
    duration_s: float | None


class JobHandler(Protocol):
    def run(self, ctx: "JobContext") -> None: ...


class JobContext:
    """O que o handler enxerga do job: etapa, progresso e cancelamento."""

    def __init__(
        self,
        *,
        job_id: uuid.UUID,
        kind: JobKind,
        session: SessionInfo,
        db: Session,
        bus: EventBus,
    ) -> None:
        self.job_id = job_id
        self.kind = kind
        self.session = session
        self._db = db
        self._events = EventPublisher(db, bus)
        self._cancel = threading.Event()
        self._lock = threading.Lock()
        self._task: CancellableTask | None = None
        self.shutting_down = False
        self._last_progress_at = 0.0

    # --- cancelamento --------------------------------------------------------

    @property
    def cancelled(self) -> bool:
        return self._cancel.is_set()

    def check_cancelled(self) -> None:
        if self._cancel.is_set():
            raise JobCancelledError

    def sleep(self, seconds: float) -> None:
        """Espera interrompível: levanta `JobCancelledError` se o job for cancelado."""
        if self._cancel.wait(seconds):
            raise JobCancelledError

    def attach(self, task: CancellableTask | None) -> None:
        """Registra o que deve ser encerrado num cancelamento (ou `None` para soltar)."""
        with self._lock:
            self._task = task
        if task is not None and self._cancel.is_set():
            task.cancel()

    def request_cancel(self, *, shutdown: bool = False) -> None:
        with self._lock:
            if shutdown:
                self.shutting_down = True
            self._cancel.set()
            task = self._task
        if task is not None:
            try:
                task.cancel()
            except Exception:
                logger.exception("Falha ao interromper o job %s", self.job_id)

    # --- etapa e progresso ---------------------------------------------------

    def set_stage(self, stage: SessionState) -> None:
        """Começa uma etapa (ex.: `SEPARATING`): fecha a duração da anterior e zera o progresso."""
        self.check_cancelled()
        job = self._db.get(JobModel, self.job_id, populate_existing=True)
        now = utcnow()
        durations = dict(job.stage_durations or {}) if job else {}
        if job is not None and job.stage is not None:
            durations[job.stage.value] = _seconds_since(job.stage_started_at, now)
        self._write(
            {
                "stage": stage,
                "stage_started_at": now,
                "stage_durations": durations,
                "progress": 0.0,
            },
            session={"state": stage, "progress": 0.0},
        )
        self._last_progress_at = 0.0

    def progress(self, percent: float) -> None:
        """Progresso da etapa atual, 0–100. Gravações são espaçadas; 100 sempre grava."""
        self.check_cancelled()
        percent = min(max(percent, 0.0), 100.0)
        now = time.monotonic()
        if percent < 100 and now - self._last_progress_at < PROGRESS_INTERVAL_S:
            return
        self._last_progress_at = now
        self._write({"progress": percent}, session={"progress": percent})

    def _write(self, job_values: dict[str, Any], *, session: dict[str, Any]) -> None:
        updated = self._db.scalar(
            update(JobModel)
            .where(JobModel.id == self.job_id, JobModel.state == JobState.RUNNING)
            .values(**job_values)
            .returning(JobModel.id)
        )
        if updated is None:
            # Cancelado pela API entre uma gravação e outra.
            self._db.rollback()
            self._cancel.set()
            raise JobCancelledError
        if self.kind is JobKind.PROCESS:
            self._db.execute(
                update(SessionModel).where(SessionModel.id == self.session.id).values(**session)
            )
        self._db.commit()
        if self.kind is JobKind.PROCESS:
            self._events.session_updated(self.session.id)
        self._events.jobs_changed(self.job_id)


class JobRunner:
    def __init__(
        self,
        sessionmaker: sessionmaker[Session],
        bus: EventBus,
        handlers: Mapping[JobKind, JobHandler],
        *,
        max_attempts: int = 2,
    ) -> None:
        self._sessionmaker = sessionmaker
        self._bus = bus
        self._handlers = dict(handlers)
        self._max_attempts = max_attempts
        self._stop = threading.Event()
        self._wakeups = {lane: threading.Event() for lane in LANES}
        self._threads: list[threading.Thread] = []
        self._running: dict[uuid.UUID, JobContext] = {}
        self._lock = threading.Lock()

    # --- ciclo de vida -------------------------------------------------------

    def start(self) -> None:
        try:
            self.recover()
        except Exception:
            # Banco ausente ou sem migration: o /health acusa; a API sobe mesmo assim.
            logger.exception("Não deu para recuperar a fila; confira o banco")
        self._stop.clear()
        for lane, kinds in LANES.items():
            thread = threading.Thread(
                target=self._work, args=(lane, kinds), name=f"stemma-{lane}", daemon=True
            )
            thread.start()
            self._threads.append(thread)
        logger.info("Fila iniciada (handlers: %s)", ", ".join(self._handlers) or "nenhum")

    def stop(self, timeout: float = STOP_TIMEOUT_S) -> None:
        """Para os workers. O job em execução é interrompido e volta para a fila sem gastar
        tentativa (um restart normal não conta como falha)."""
        self._stop.set()
        with self._lock:
            running = list(self._running.values())
        for ctx in running:
            ctx.request_cancel(shutdown=True)
        for wakeup in self._wakeups.values():
            wakeup.set()
        for thread in self._threads:
            thread.join(timeout)
            if thread.is_alive():
                logger.warning("Worker %s não parou em %.0f s", thread.name, timeout)
        self._threads.clear()

    def wake(self) -> None:
        """Avisa os workers de que há job novo na fila."""
        for wakeup in self._wakeups.values():
            wakeup.set()

    def cancel(self, job_id: uuid.UUID) -> None:
        """Interrompe o job se estiver rodando. O estado `cancelled` já foi gravado pela API."""
        with self._lock:
            ctx = self._running.get(job_id)
        if ctx is not None:
            ctx.request_cancel()

    def recover(self) -> None:
        """Jobs `running` no startup são de uma execução que caiu: voltam para a fila até
        `max_attempts` tentativas; depois disso falham como interrompidos."""
        with self._sessionmaker() as db:
            jobs = db.scalars(select(JobModel).where(JobModel.state == JobState.RUNNING)).all()
            for job in jobs:
                if job.attempt < self._max_attempts:
                    _requeue(db, job)
                    logger.warning(
                        "Job %s interrompido; de volta à fila (%d de %d tentativas usadas)",
                        job.id,
                        job.attempt,
                        self._max_attempts,
                    )
                else:
                    _fail(
                        db,
                        job,
                        "interrupted",
                        "O processamento foi interrompido. Tente de novo.",
                    )
                    logger.warning("Job %s interrompido %d vezes; falhou", job.id, job.attempt)
            db.commit()

    # --- worker --------------------------------------------------------------

    def _work(self, lane: str, kinds: tuple[JobKind, ...]) -> None:
        wakeup = self._wakeups[lane]
        failing = False
        while not self._stop.is_set():
            try:
                ctx = self._claim(kinds)
                failing = False
            except Exception:
                # Loga só a primeira falha seguida (ex.: banco sem migration), sem inundar o log.
                if not failing:
                    logger.exception("Falha ao buscar o próximo job (%s)", lane)
                failing = True
                ctx = None
            if ctx is None:
                wakeup.wait(POLL_INTERVAL_S)
                wakeup.clear()
                continue
            try:
                self._execute(ctx)
            except Exception:
                # Ex.: banco travado ao gravar o fim. O worker segue; o job fica `running`
                # e a recuperação do próximo startup cuida dele.
                logger.exception("Falha ao encerrar o job %s", ctx.job_id)
            finally:
                with self._lock:
                    self._running.pop(ctx.job_id, None)
                ctx._db.close()

    def _claim(self, kinds: tuple[JobKind, ...]) -> JobContext | None:
        db = self._sessionmaker()
        try:
            now = utcnow()
            next_id = (
                select(JobModel.id)
                .where(JobModel.state == JobState.QUEUED, JobModel.kind.in_(kinds))
                .order_by(JobModel.created_at, JobModel.id)
                .limit(1)
                .scalar_subquery()
            )
            job_id = db.scalar(
                update(JobModel)
                .where(JobModel.id == next_id, JobModel.state == JobState.QUEUED)
                .values(
                    state=JobState.RUNNING,
                    attempt=JobModel.attempt + 1,
                    started_at=now,
                    stage=None,
                    stage_started_at=now,
                    stage_durations=None,
                    progress=0.0,
                    error_code=None,
                    error_message=None,
                )
                .returning(JobModel.id)
            )
            if job_id is None:
                db.rollback()
                db.close()
                return None
            db.commit()
            job = db.get(JobModel, job_id, populate_existing=True)
            session = db.get(SessionModel, job.session_id) if job else None
            if job is None or session is None:
                # Sessão excluída no meio (cascade); nada a fazer.
                db.close()
                return None
            ctx = JobContext(
                job_id=job.id,
                kind=job.kind,
                session=SessionInfo(
                    id=session.id,
                    code=session.code,
                    source_url=session.source_url,
                    artist=session.artist,
                    title=session.title,
                    duration_s=session.duration_s,
                ),
                db=db,
                bus=self._bus,
            )
        except Exception:
            db.close()
            raise
        with self._lock:
            self._running[ctx.job_id] = ctx
        if self._stop.is_set():
            ctx.request_cancel(shutdown=True)
        logger.info("Job %s (%s, %s) começou", ctx.job_id, ctx.kind, ctx.session.code)
        ctx._events.jobs_changed(ctx.job_id)
        return ctx

    def _execute(self, ctx: JobContext) -> None:
        try:
            handler = self._handlers.get(ctx.kind)
            if handler is None:
                raise AppError(
                    "pipeline_unavailable", "O pipeline de áudio ainda não está disponível."
                )
            handler.run(ctx)
            ctx.check_cancelled()
        except JobCancelledError:
            self._finish_interrupted(ctx)
        except AppError as exc:
            if ctx.cancelled:
                self._finish_interrupted(ctx)
            else:
                self._finish(ctx, JobState.FAILED, exc.code, exc.message)
        except Exception:
            if ctx.cancelled:
                self._finish_interrupted(ctx)
            else:
                logger.exception("Job %s falhou com erro inesperado", ctx.job_id)
                self._finish(
                    ctx, JobState.FAILED, "internal_error", "Erro inesperado no processamento."
                )
        else:
            self._finish(ctx, JobState.DONE)

    def _finish(
        self,
        ctx: JobContext,
        state: JobState,
        error_code: str | None = None,
        error_message: str | None = None,
    ) -> None:
        db = ctx._db
        db.rollback()
        job = db.get(JobModel, ctx.job_id, populate_existing=True)
        if job is None or job.state is not JobState.RUNNING:
            return
        now = utcnow()
        durations = dict(job.stage_durations or {})
        durations[job.stage.value if job.stage else RUN_STAGE] = _seconds_since(
            job.stage_started_at, now
        )
        updated = db.scalar(
            update(JobModel)
            .where(JobModel.id == ctx.job_id, JobModel.state == JobState.RUNNING)
            .values(
                state=state,
                progress=100.0 if state is JobState.DONE else job.progress,
                stage_durations=durations,
                error_code=error_code,
                error_message=error_message,
                finished_at=now,
            )
            .returning(JobModel.id)
        )
        if updated is None:
            db.rollback()
            return
        if ctx.kind is JobKind.PROCESS:
            values: dict[str, Any] = (
                {
                    "state": SessionState.READY,
                    "progress": 100.0,
                    "processed_at": now,
                    "error_code": None,
                    "error_message": None,
                }
                if state is JobState.DONE
                else {
                    "state": SessionState.FAILED,
                    "error_code": error_code,
                    "error_message": error_message,
                }
            )
            db.execute(update(SessionModel).where(SessionModel.id == ctx.session.id).values(values))
        db.commit()
        logger.info("Job %s terminou: %s %s", ctx.job_id, state, error_code or "")
        if ctx.kind is JobKind.PROCESS:
            ctx._events.session_updated(ctx.session.id)
        ctx._events.jobs_changed(ctx.job_id)

    def _finish_interrupted(self, ctx: JobContext) -> None:
        """Cancelado pela API (estado já gravado) ou desligamento (volta para a fila)."""
        db = ctx._db
        db.rollback()
        if not ctx.shutting_down:
            logger.info("Job %s cancelado", ctx.job_id)
            return
        job = db.get(JobModel, ctx.job_id, populate_existing=True)
        if job is not None and _requeue(db, job, refund_attempt=True):
            db.commit()
            logger.info("Job %s devolvido à fila (servidor parando)", ctx.job_id)


def _requeue(db: Session, job: JobModel, *, refund_attempt: bool = False) -> bool:
    """Devolve à fila um job `running`. Condicional: não mexe num job já cancelado."""
    attempt = max(job.attempt - 1, 0) if refund_attempt else job.attempt
    updated = db.scalar(
        update(JobModel)
        .where(JobModel.id == job.id, JobModel.state == JobState.RUNNING)
        .values(
            state=JobState.QUEUED,
            stage=None,
            progress=0.0,
            attempt=attempt,
            started_at=None,
            stage_started_at=None,
            stage_durations=None,
        )
        .returning(JobModel.id)
    )
    if updated is None:
        return False
    if job.kind is JobKind.PROCESS:
        db.execute(
            update(SessionModel)
            .where(SessionModel.id == job.session_id)
            .values(state=SessionState.QUEUED, progress=0.0)
        )
    return True


def _fail(db: Session, job: JobModel, code: str, message: str) -> None:
    job.state = JobState.FAILED
    job.error_code = code
    job.error_message = message
    job.finished_at = utcnow()
    if job.kind is JobKind.PROCESS:
        db.execute(
            update(SessionModel)
            .where(SessionModel.id == job.session_id)
            .values(state=SessionState.FAILED, error_code=code, error_message=message)
        )


def _seconds_since(start: datetime | None, end: datetime) -> float:
    return max((end - start).total_seconds(), 0.0) if start else 0.0
