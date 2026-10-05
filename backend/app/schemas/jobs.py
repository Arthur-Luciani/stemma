import uuid
from datetime import datetime

from pydantic import BaseModel

from app.domain.enums import JobKind, JobState, SessionState
from app.schemas.sessions import SessionOut


class JobOut(BaseModel):
    id: uuid.UUID
    kind: JobKind
    session_id: uuid.UUID
    export_id: uuid.UUID | None
    state: JobState
    # Etapa atual do processamento (downloading/separating); null antes de começar.
    stage: SessionState | None
    # Progresso da etapa atual, 0–100.
    progress: float
    attempt: int
    error_code: str | None
    error_message: str | None
    # Posição entre os jobs na fila do mesmo worker, a partir de 1; null se não está na fila.
    position: int | None
    # Segundos estimados até o job terminar; null se não está ativo.
    eta_s: int | None
    created_at: datetime
    started_at: datetime | None
    finished_at: datetime | None
    # Preenchido quando o usuário tira o job do dock (ou ao reprocessar a sessão).
    dismissed_at: datetime | None
    session: SessionOut


class JobListOut(BaseModel):
    # Em execução, depois a fila em ordem, depois os encerrados ainda não descartados.
    items: list[JobOut]
