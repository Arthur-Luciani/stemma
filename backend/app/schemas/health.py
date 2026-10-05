from typing import Literal

from pydantic import BaseModel

Check = Literal["ok", "missing"]
# outdated = banco sem `alembic upgrade head` (vazio ou em revisão antiga).
DbCheck = Literal["ok", "outdated", "error"]


class HealthOut(BaseModel):
    status: Literal["ok", "degraded"]
    version: str
    db: DbCheck
    ffmpeg: Check
    # Algum dos runtimes JS do YTDLP_JS_RUNTIME (deno, node…) está no PATH.
    js_runtime: Check
    # CUDA disponível para o Demucs; `unknown` enquanto a sonda roda (logo após o start).
    gpu: Literal["ok", "unavailable", "unknown"]
    # Versão do yt-dlp instalada (o YouTube quebra versões antigas).
    ytdlp: str
