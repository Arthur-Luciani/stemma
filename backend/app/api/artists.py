from typing import Annotated

from fastapi import APIRouter, Query

from app.api.deps import IdentityServiceDep
from app.api.errors import ERROR_RESPONSES
from app.schemas.artists import ArtistOut

router = APIRouter(prefix="/api/artists", tags=["identity"], responses=ERROR_RESPONSES)


@router.get("")
def search_artists(
    service: IdentityServiceDep,
    q: Annotated[str | None, Query(max_length=200)] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 10,
) -> list[ArtistOut]:
    return service.search_artists(q, limit)
