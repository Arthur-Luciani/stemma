from fastapi import APIRouter, status

from app.api.deps import SystemUpdateServiceDep, YtDlpUpdateServiceDep
from app.api.errors import ERROR_RESPONSES
from app.schemas.system import SystemUpdateOut, UpdateRunOut, YtDlpStatusOut

router = APIRouter(prefix="/api/system", tags=["system"], responses=ERROR_RESPONSES)


@router.get("/update")
def get_update(service: SystemUpdateServiceDep) -> SystemUpdateOut:
    return service.status()


@router.post("/update/check")
def check_update(service: SystemUpdateServiceDep) -> SystemUpdateOut:
    return service.check()


@router.post("/update", status_code=status.HTTP_202_ACCEPTED)
def start_update(service: SystemUpdateServiceDep) -> UpdateRunOut:
    return service.start()


@router.get("/ytdlp")
def get_ytdlp(service: YtDlpUpdateServiceDep) -> YtDlpStatusOut:
    return service.status()


@router.post("/ytdlp", status_code=status.HTTP_202_ACCEPTED)
def start_ytdlp_update(service: YtDlpUpdateServiceDep) -> UpdateRunOut:
    return service.start()
