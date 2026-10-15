import uuid

from fastapi import APIRouter, Response, status

from app.api.deps import PresetServiceDep
from app.api.errors import ERROR_RESPONSES
from app.schemas.presets import PresetCreate, PresetListOut, PresetOrder, PresetOut, PresetUpdate

router = APIRouter(prefix="/api/presets", tags=["presets"], responses=ERROR_RESPONSES)


@router.get("")
def list_presets(service: PresetServiceDep) -> PresetListOut:
    return PresetListOut(items=service.list_all())


@router.post("", status_code=status.HTTP_201_CREATED)
def create_preset(data: PresetCreate, service: PresetServiceDep) -> PresetOut:
    return service.create(data)


@router.put("/order")
def reorder_presets(data: PresetOrder, service: PresetServiceDep) -> PresetListOut:
    return PresetListOut(items=service.reorder(data))


@router.patch("/{preset_id}")
def update_preset(preset_id: uuid.UUID, data: PresetUpdate, service: PresetServiceDep) -> PresetOut:
    return service.update(preset_id, data)


@router.delete("/{preset_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_preset(preset_id: uuid.UUID, service: PresetServiceDep) -> Response:
    service.delete(preset_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
