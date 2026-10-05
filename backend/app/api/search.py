from typing import Annotated

from fastapi import APIRouter, Query

from app.api.deps import SearchServiceDep
from app.api.errors import ERROR_RESPONSES
from app.schemas.search import SearchOut

router = APIRouter(prefix="/api/search", tags=["search"], responses=ERROR_RESPONSES)


@router.get("")
def search(
    service: SearchServiceDep,
    q: Annotated[str, Query(min_length=1, max_length=500)],
) -> SearchOut:
    """Busca no YouTube (texto) ou lê um link. `items` vazio = nenhum resultado;
    YouTube indisponível responde 502 `youtube_unavailable`."""
    return SearchOut(items=service.search(q))
