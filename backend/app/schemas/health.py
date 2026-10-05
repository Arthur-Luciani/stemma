from typing import Literal

from pydantic import BaseModel

Check = Literal["ok", "missing"]
DbCheck = Literal["ok", "error"]


class HealthOut(BaseModel):
    status: Literal["ok", "degraded"]
    version: str
    db: DbCheck
    ffmpeg: Check
    js_runtime: Check
    # Verificado de verdade só a partir da F2b.
    gpu: Literal["ok", "unavailable", "unknown"]
