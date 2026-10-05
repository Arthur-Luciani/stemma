import uuid
from datetime import datetime
from typing import Annotated, Any

from pydantic import (
    AnyHttpUrl,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_validator,
    model_validator,
)

from app.domain.enums import SessionState, Stem

ShortText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
OptionalText = Annotated[str, StringConstraints(strip_whitespace=True, max_length=500)] | None


class SessionCreate(BaseModel):
    """Rascunho de sessão: fonte escolhida em Descobrir + identidade confirmada."""

    model_config = ConfigDict(extra="forbid")

    source_url: AnyHttpUrl
    source_title: OptionalText = None
    source_channel: OptionalText = None
    thumbnail_url: AnyHttpUrl | None = None
    duration_s: Annotated[float, Field(ge=0)] | None = None
    artist: ShortText
    title: ShortText


class SessionPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    artist: ShortText | None = None
    title: ShortText | None = None

    @model_validator(mode="after")
    def _at_least_one(self) -> "SessionPatch":
        if self.artist is None and self.title is None:
            raise ValueError("informe artista ou título")
        return self


class SessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    code: str
    source_url: str
    source_title: str | None
    source_channel: str | None
    thumbnail_url: str | None
    artist: str
    title: str
    duration_s: float | None
    state: SessionState
    progress: float
    error_code: str | None
    error_message: str | None
    # Só quais stems existem; os arquivos são servidos por rota própria (F4).
    stems: list[Stem]
    metrics: dict[str, Any] | None
    created_at: datetime
    updated_at: datetime
    processed_at: datetime | None

    @field_validator("stems", mode="before")
    @classmethod
    def _stem_names(cls, value: dict[str, str] | list[str] | None) -> list[str]:
        if value is None:
            return []
        names = value.keys() if isinstance(value, dict) else value
        return [s.value for s in Stem if s.value in names]


class SessionListOut(BaseModel):
    items: list[SessionOut]
    total: int
    # Contagem por estado com o filtro de busca aplicado (sem o filtro de estado).
    counts: dict[SessionState, int]
