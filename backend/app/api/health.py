from fastapi import APIRouter

from app.api.deps import HealthServiceDep
from app.schemas.health import HealthOut

router = APIRouter(tags=["health"])


@router.get("/health")
def health(service: HealthServiceDep) -> HealthOut:
    return service.check()
