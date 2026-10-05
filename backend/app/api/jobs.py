import uuid

from fastapi import APIRouter, status

from app.api.deps import JobServiceDep
from app.api.errors import ERROR_RESPONSES
from app.schemas.jobs import JobListOut

router = APIRouter(prefix="/api/jobs", tags=["jobs"], responses=ERROR_RESPONSES)


@router.get("")
def list_jobs(service: JobServiceDep) -> JobListOut:
    return JobListOut(items=service.list())


@router.delete("/{job_id}", status_code=status.HTTP_204_NO_CONTENT)
def cancel_job(job_id: uuid.UUID, service: JobServiceDep) -> None:
    service.cancel(job_id)


@router.post("/{job_id}/discard", status_code=status.HTTP_204_NO_CONTENT)
def discard_job(job_id: uuid.UUID, service: JobServiceDep) -> None:
    service.discard(job_id)
