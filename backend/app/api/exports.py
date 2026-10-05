import uuid

from fastapi import APIRouter, status
from fastapi.responses import FileResponse

from app.api.deps import ExportServiceDep
from app.api.errors import ERROR_RESPONSES
from app.domain.enums import ExportFormat
from app.schemas.exports import ExportCreate, ExportListOut, ExportOut

router = APIRouter(prefix="/api", tags=["exports"], responses=ERROR_RESPONSES)

_MEDIA_TYPES = {ExportFormat.WAV.value: "audio/wav", ExportFormat.MP3.value: "audio/mpeg"}


@router.post("/sessions/{session_id}/exports", status_code=status.HTTP_201_CREATED)
def create_export(
    session_id: uuid.UUID, data: ExportCreate, service: ExportServiceDep
) -> ExportOut:
    """Exporta o mix (WAV ou MP3 320). Sem `stems` no corpo, usa o mix salvo da sessão."""
    return service.create(session_id, data)


@router.get("/sessions/{session_id}/exports")
def list_exports(session_id: uuid.UUID, service: ExportServiceDep) -> ExportListOut:
    return ExportListOut(items=service.list(session_id))


@router.get(
    "/exports/{export_id}/file",
    response_class=FileResponse,
    responses={200: {"content": {"audio/wav": {}, "audio/mpeg": {}}}},
)
def download_export(export_id: uuid.UUID, service: ExportServiceDep) -> FileResponse:
    path, file_name = service.file(export_id)
    return FileResponse(
        path, filename=file_name, media_type=_MEDIA_TYPES.get(path.suffix.lstrip("."))
    )
