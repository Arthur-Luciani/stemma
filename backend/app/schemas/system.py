from datetime import datetime
from typing import Literal

from pydantic import BaseModel

from app.domain.enums import UpdateState


class UpdateRunOut(BaseModel):
    """Uma atualização pedida pelo app."""

    id: int
    from_version: str
    target_version: str
    state: UpdateState
    # Motivo da falha (PT-BR), ou detalhe do sucesso.
    message: str | None
    created_at: datetime
    finished_at: datetime | None


class ReleaseNotesSection(BaseModel):
    title: str
    items: list[str]


class ReleaseNotes(BaseModel):
    version: str
    sections: list[ReleaseNotesSection]


class SystemUpdateOut(BaseModel):
    current_version: str
    # unavailable = não foi possível consultar o GitHub agora (rede, limite da API).
    check: Literal["ok", "unavailable"]
    checked_at: datetime | None
    latest_version: str | None
    available: bool
    # Notas das releases depois da atual até a última, da mais nova para a mais velha.
    notes: list[ReleaseNotes]
    # A instalação tem a tarefa agendada que atualiza (instalada pelo `.exe`).
    can_update: bool
    # Jobs na fila ou rodando: a atualização espera eles terminarem.
    active_jobs: int
    last_run: UpdateRunOut | None
