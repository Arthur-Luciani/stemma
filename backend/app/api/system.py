from fastapi import APIRouter, status

from app.api.deps import SystemUpdateServiceDep
from app.api.errors import ERROR_RESPONSES
from app.schemas.system import SystemUpdateOut, UpdateRunOut

router = APIRouter(prefix="/api/system", tags=["system"], responses=ERROR_RESPONSES)


@router.get("/update")
def get_update(service: SystemUpdateServiceDep) -> SystemUpdateOut:
    return service.status()


@router.post("/update", status_code=status.HTTP_202_ACCEPTED)
def start_update(service: SystemUpdateServiceDep) -> UpdateRunOut:
    return service.start()
