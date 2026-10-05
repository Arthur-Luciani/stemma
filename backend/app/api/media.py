"""Arquivos do player. O `FileResponse` atende `Range` (206), o que o `<audio>` e o
`fetch` parcial do AudioEngine usam."""

import uuid

from fastapi import APIRouter
from fastapi.responses import FileResponse

from app.api.deps import MediaServiceDep
from app.api.errors import ERROR_RESPONSES
from app.domain.enums import Stem

router = APIRouter(prefix="/api/sessions", tags=["media"], responses=ERROR_RESPONSES)

# Reprocessar troca o arquivo na mesma URL: o navegador revalida (ETag) a cada uso.
_CACHE = {"Cache-Control": "no-cache"}


@router.get(
    "/{session_id}/stems/{stem}.mp3",
    response_class=FileResponse,
    responses={200: {"content": {"audio/mpeg": {}}}},
)
def stem_audio(session_id: uuid.UUID, stem: Stem, service: MediaServiceDep) -> FileResponse:
    return FileResponse(
        service.stem_audio(session_id, stem), media_type="audio/mpeg", headers=_CACHE
    )


@router.get(
    "/{session_id}/peaks/{stem}.json",
    response_class=FileResponse,
    responses={200: {"content": {"application/json": {}}}},
)
def stem_peaks(session_id: uuid.UUID, stem: Stem, service: MediaServiceDep) -> FileResponse:
    """`{"duration_s": float, "peaks": [0–1, ...]}` (pico absoluto por ponto, ~1600 pontos)."""
    return FileResponse(
        service.stem_peaks(session_id, stem), media_type="application/json", headers=_CACHE
    )
