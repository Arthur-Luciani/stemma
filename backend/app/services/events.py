"""Eventos ao vivo (ADR 0003): o EventBus só **propaga** o que já foi gravado no banco.

Quem escreve publica depois do commit, sempre pelo `EventPublisher`, que monta os payloads
com os mesmos schemas da API. O `publish` é thread-safe: os workers da fila rodam em threads
e cada assinante (um WebSocket) recebe na fila do seu event loop.
"""

import asyncio
import contextlib
import logging
import threading
import uuid
from typing import Any

from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import JobModel, SessionModel
from app.domain.enums import ACTIVE_JOB_STATES, EventType
from app.pipeline.eta import JobEstimate, QueueEstimator
from app.schemas.events import (
    JobUpdatedData,
    JobUpdatedEvent,
    SessionDeletedData,
    SessionDeletedEvent,
    SessionUpdatedData,
    SessionUpdatedEvent,
)
from app.schemas.jobs import JobOut
from app.schemas.sessions import SessionOut

logger = logging.getLogger(__name__)

# Eventos pendentes por assinante; acima disso o mais antigo é descartado.
SUBSCRIBER_QUEUE_SIZE = 500

Message = dict[str, Any]


class Subscription:
    """Fila de eventos de um assinante, presa ao event loop em que foi criada."""

    def __init__(self, bus: "EventBus", loop: asyncio.AbstractEventLoop) -> None:
        self._bus = bus
        self._loop = loop
        self._queue: asyncio.Queue[Message] = asyncio.Queue(maxsize=SUBSCRIBER_QUEUE_SIZE)

    async def get(self) -> Message:
        return await self._queue.get()

    def close(self) -> None:
        self._bus._unsubscribe(self)

    def __enter__(self) -> "Subscription":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def _deliver(self, message: Message) -> None:
        # Chamado sempre na thread do event loop do assinante.
        if self._queue.full():
            self._queue.get_nowait()
            logger.warning("Assinante lento: evento antigo descartado")
        self._queue.put_nowait(message)

    def _send(self, message: Message) -> None:
        # RuntimeError: loop já encerrado (cliente saindo); o unsubscribe vem em seguida.
        with contextlib.suppress(RuntimeError):
            self._loop.call_soon_threadsafe(self._deliver, message)


class EventBus:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._subscribers: set[Subscription] = set()

    def subscribe(self) -> Subscription:
        """Chame de dentro do event loop que vai consumir os eventos."""
        subscription = Subscription(self, asyncio.get_running_loop())
        with self._lock:
            self._subscribers.add(subscription)
        return subscription

    def publish(self, message: Message) -> None:
        with self._lock:
            subscribers = list(self._subscribers)
        for subscription in subscribers:
            subscription._send(message)

    def _unsubscribe(self, subscription: Subscription) -> None:
        with self._lock:
            self._subscribers.discard(subscription)


def build_job_out(job: JobModel, session: SessionModel, estimate: JobEstimate | None) -> JobOut:
    return JobOut.model_validate(
        {
            "id": job.id,
            "kind": job.kind,
            "session_id": job.session_id,
            "export_id": job.export_id,
            "state": job.state,
            "stage": job.stage,
            "progress": job.progress,
            "attempt": job.attempt,
            "error_code": job.error_code,
            "error_message": job.error_message,
            "position": estimate.position if estimate else None,
            "eta_s": estimate.eta_s if estimate else None,
            "created_at": job.created_at,
            "started_at": job.started_at,
            "finished_at": job.finished_at,
            "session": SessionOut.model_validate(session),
        }
    )


class EventPublisher:
    """Monta e publica eventos. Chame **depois** do commit, com o estado já no banco."""

    def __init__(self, db: Session, bus: EventBus) -> None:
        self.db = db
        self.bus = bus

    def session_updated(self, session_id: uuid.UUID) -> None:
        session = self.db.get(SessionModel, session_id, populate_existing=True)
        if session is None:
            return
        self._publish(
            SessionUpdatedEvent(
                type=EventType.SESSION_UPDATED,
                data=SessionUpdatedData(session=SessionOut.model_validate(session)),
            )
        )

    def session_deleted(self, session_id: uuid.UUID) -> None:
        self._publish(
            SessionDeletedEvent(
                type=EventType.SESSION_DELETED, data=SessionDeletedData(id=session_id)
            )
        )

    def jobs_changed(self, *job_ids: uuid.UUID) -> None:
        """Publica os jobs indicados e todos os ativos: posição e ETA da fila inteira mudam
        quando um job entra, anda, sai ou termina."""
        estimates = QueueEstimator(self.db).estimate()
        rows = self.db.execute(
            select(JobModel, SessionModel)
            .join(SessionModel, SessionModel.id == JobModel.session_id)
            .where(JobModel.state.in_(ACTIVE_JOB_STATES) | JobModel.id.in_(job_ids))
            .order_by(JobModel.created_at, JobModel.id)
            .execution_options(populate_existing=True)
        ).all()
        for job, session in rows:
            self._publish(
                JobUpdatedEvent(
                    type=EventType.JOB_UPDATED,
                    data=JobUpdatedData(job=build_job_out(job, session, estimates.get(job.id))),
                )
            )

    def _publish(self, event: BaseModel) -> None:
        self.bus.publish(event.model_dump(mode="json"))
