"""Trava de jobs novos durante as atualizações (ADR 0015 e 0016).

Fica fora dos services de atualização para que jobs e exports possam consultar sem depender
deles (que, por sua vez, dependem do `JobService`)."""

import logging
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import SystemUpdateModel
from app.db.types import utcnow
from app.domain.enums import UpdateComponent, UpdateState
from app.domain.errors import ConflictError

logger = logging.getLogger(__name__)

STALE_MESSAGE = (
    "A atualização não terminou (o PC pode ter desligado no meio). "
    "Veja os logs na pasta logs da instalação."
)

# Uma atualização `running` há mais tempo que isso não vai terminar (PC desligou no meio,
# tarefa morta). Maior que o limite de cada tarefa agendada (`Register-StemmaTasks`: 3 h a do
# Stemma, 20 min a do yt-dlp), que a encerra antes; assim um resultado atrasado nunca cai
# depois do "não terminou".
RUNNING_TIMEOUTS: dict[UpdateComponent, timedelta] = {
    UpdateComponent.APP: timedelta(hours=3, minutes=30),
    UpdateComponent.YTDLP: timedelta(minutes=30),
}


def latest_update(db: Session, component: UpdateComponent) -> SystemUpdateModel | None:
    return db.scalar(
        select(SystemUpdateModel)
        .where(SystemUpdateModel.component == component)
        .order_by(SystemUpdateModel.id.desc())
        .limit(1)
    )


def is_running(run: SystemUpdateModel | None, now: datetime) -> bool:
    return (
        run is not None
        and run.state == UpdateState.RUNNING
        and now - run.created_at <= RUNNING_TIMEOUTS[run.component]
    )


def last_run(db: Session, component: UpdateComponent, now: datetime) -> SystemUpdateModel | None:
    """A última atualização do componente. Um `running` sem resultado além do limite vira
    `failed` ("não terminou") aqui, e libera uma nova tentativa."""
    run = latest_update(db, component)
    if run is not None and run.state == UpdateState.RUNNING and not is_running(run, now):
        logger.warning(
            "Atualização %s (%s) sem resultado há mais de %s",
            run.id,
            component,
            RUNNING_TIMEOUTS[component],
        )
        run.state = UpdateState.FAILED
        run.message = STALE_MESSAGE
        run.finished_at = now
        db.commit()
    return run


def record_result(
    db: Session,
    component: UpdateComponent,
    state: UpdateState,
    message: str | None,
    now: datetime,
) -> bool:
    """Grava o resultado na última atualização do componente, se ela ainda estiver `running`
    (usado pelo CLI, no fim da tarefa). False se não houver (tarefa rodada à mão): nada muda."""
    if state == UpdateState.RUNNING:
        raise ValueError("o resultado precisa ser succeeded ou failed")
    run = latest_update(db, component)
    if run is None or run.state != UpdateState.RUNNING:
        logger.warning("Resultado (%s) sem atualização em andamento: %s", component, state)
        return False
    run.state = state
    run.message = message or None
    run.finished_at = now
    db.commit()
    logger.info(
        "Atualização %s %s → %s: %s", component, run.from_version, run.target_version, state
    )
    return True


def running_update(db: Session, now: datetime) -> SystemUpdateModel | None:
    """A atualização em andamento (do Stemma ou do yt-dlp), se houver."""
    for component in UpdateComponent:
        run = latest_update(db, component)
        if is_running(run, now):
            return run
    return None


def ensure_not_updating(db: Session) -> None:
    """Recusa job novo com atualização em andamento: as duas param o serviço no meio."""
    if running_update(db, utcnow()) is not None:
        raise ConflictError(
            "update_running", "O Stemma está atualizando. Tente de novo em alguns minutos."
        )
