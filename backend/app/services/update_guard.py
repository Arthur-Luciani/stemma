"""Trava de jobs novos durante a atualização pelo app (ADR 0015).

Fica fora do `SystemUpdateService` para que jobs e exports possam consultar sem depender dele
(que, por sua vez, depende do `JobService`)."""

from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import SystemUpdateModel
from app.db.types import utcnow
from app.domain.enums import UpdateState
from app.domain.errors import ConflictError

# Uma atualização `running` há mais tempo que isso não vai terminar (PC desligou no meio,
# tarefa morta). Maior que o limite da tarefa agendada (3 h, `Register-StemmaTasks`), que a
# encerra antes; assim um resultado atrasado nunca cai depois do "não terminou".
RUNNING_TIMEOUT = timedelta(hours=3, minutes=30)


def latest_update(db: Session) -> SystemUpdateModel | None:
    return db.scalar(select(SystemUpdateModel).order_by(SystemUpdateModel.id.desc()).limit(1))


def is_running(run: SystemUpdateModel | None, now: datetime) -> bool:
    return (
        run is not None
        and run.state == UpdateState.RUNNING
        and now - run.created_at <= RUNNING_TIMEOUT
    )


def ensure_not_updating(db: Session) -> None:
    """Recusa job novo com atualização em andamento: o instalador para o serviço no meio."""
    if is_running(latest_update(db), utcnow()):
        raise ConflictError(
            "update_running", "O Stemma está atualizando. Tente de novo em alguns minutos."
        )
