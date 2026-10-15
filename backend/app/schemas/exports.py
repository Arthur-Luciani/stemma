import uuid
from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.domain.enums import ExportFormat, ExportState, Stem
from app.domain.presets import MAX_PRESET_NAME
from app.schemas.mix import StemMix


class ExportCreate(BaseModel):
    """Pedido de export. Sem `stems`, vale o mix salvo da sessão."""

    model_config = ConfigDict(extra="forbid")

    format: ExportFormat
    # Nome do preset aplicado (snapshot para o histórico); sem ele, o export não mostra preset.
    preset: Annotated[str, Field(min_length=1, max_length=MAX_PRESET_NAME)] | None = None
    stems: dict[Stem, StemMix] | None = None

    @field_validator("stems")
    @classmethod
    def _all_stems(cls, value: dict[Stem, StemMix] | None) -> dict[Stem, StemMix] | None:
        if value is not None:
            missing = [s.value for s in Stem if s not in value]
            if missing:
                raise ValueError(f"faltam os stems: {', '.join(missing)}")
        return value


class ExportOut(BaseModel):
    id: uuid.UUID
    session_id: uuid.UUID
    format: ExportFormat
    preset: str | None
    # Níveis usados no export (snapshot do mix no momento do pedido).
    stems: dict[Stem, StemMix]
    state: ExportState
    # 0–100.
    progress: float
    size_bytes: int | None
    lufs: float | None
    error_code: str | None
    error_message: str | None
    # Nome do arquivo no download: "Artista - Título (Preset).ext".
    file_name: str
    created_at: datetime
    finished_at: datetime | None


class ExportListOut(BaseModel):
    # Mais recentes primeiro.
    items: list[ExportOut]
