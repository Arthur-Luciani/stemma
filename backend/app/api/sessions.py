import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.deps import JobServiceDep, SessionServiceDep
from app.api.errors import ERROR_RESPONSES
from app.domain.enums import SessionSort, SessionState
from app.schemas.jobs import JobOut
from app.schemas.sessions import SessionCreate, SessionListOut, SessionOut, SessionPatch

router = APIRouter(prefix="/api/sessions", tags=["sessions"], responses=ERROR_RESPONSES)


@router.get("")
def list_sessions(
    service: SessionServiceDep,
    q: Annotated[str | None, Query(max_length=200)] = None,
    state: Annotated[list[SessionState] | None, Query()] = None,
    sort: SessionSort = SessionSort.NEWEST,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> SessionListOut:
    items, total, counts = service.list(q=q, states=state, sort=sort, limit=limit, offset=offset)
    return SessionListOut(
        items=[SessionOut.model_validate(s) for s in items], total=total, counts=counts
    )


@router.post("", status_code=status.HTTP_201_CREATED)
def create_session(data: SessionCreate, service: SessionServiceDep) -> SessionOut:
    return SessionOut.model_validate(service.create_draft(data))


@router.get("/{session_id}")
def get_session(session_id: uuid.UUID, service: SessionServiceDep) -> SessionOut:
    return SessionOut.model_validate(service.get(session_id))


@router.patch("/{session_id}")
def update_session(
    session_id: uuid.UUID, data: SessionPatch, service: SessionServiceDep
) -> SessionOut:
    return SessionOut.model_validate(service.update_identity(session_id, data))


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_session(session_id: uuid.UUID, service: SessionServiceDep) -> None:
    service.delete(session_id)


@router.post("/{session_id}/process", status_code=status.HTTP_201_CREATED)
def process_session(session_id: uuid.UUID, service: JobServiceDep) -> JobOut:
    """Confirma o rascunho e o põe na fila de processamento."""
    return service.process(session_id)


@router.post("/{session_id}/reprocess", status_code=status.HTTP_201_CREATED)
def reprocess_session(session_id: uuid.UUID, service: JobServiceDep) -> JobOut:
    """Processa de novo uma sessão pronta ou que falhou (409 se já houver job ativo)."""
    return service.reprocess(session_id)
