from fastapi import APIRouter

from app import __version__
from app.schemas.health import HealthOut

router = APIRouter(tags=["health"])


@router.get("/health")
def health() -> HealthOut:
    return HealthOut(status="ok", version=__version__)
