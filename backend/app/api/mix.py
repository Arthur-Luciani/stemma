import uuid

from fastapi import APIRouter

from app.api.deps import MixServiceDep
from app.api.errors import ERROR_RESPONSES
from app.schemas.mix import MixStateIn, MixStateOut

router = APIRouter(prefix="/api/sessions", tags=["mix"], responses=ERROR_RESPONSES)


@router.get("/{session_id}/mix")
def get_mix(session_id: uuid.UUID, service: MixServiceDep) -> MixStateOut:
    return service.get(session_id)


@router.put("/{session_id}/mix")
def save_mix(session_id: uuid.UUID, data: MixStateIn, service: MixServiceDep) -> MixStateOut:
    return service.save(session_id, data)
