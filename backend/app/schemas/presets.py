import uuid
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.domain.enums import PresetColor, PresetIcon, Stem
from app.domain.presets import MAX_PRESET_NAME

PresetName = Annotated[str, Field(min_length=1, max_length=MAX_PRESET_NAME)]


class PresetStem(BaseModel):
    """Nível de um stem no preset. Solo não entra: aplicar um preset limpa o solo."""

    model_config = ConfigDict(extra="forbid")

    volume: Annotated[float, Field(ge=0, le=100)] = 100
    pan: Annotated[float, Field(ge=-1, le=1)] = 0
    mute: bool = False


def _all_stems(value: dict[Stem, PresetStem]) -> dict[Stem, PresetStem]:
    missing = [s.value for s in Stem if s not in value]
    if missing:
        raise ValueError(f"faltam os stems: {', '.join(missing)}")
    return value


class PresetCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: PresetName
    stems: dict[Stem, PresetStem]
    visible: bool = True
    icon: PresetIcon | None = None
    color: PresetColor | None = None

    _stems = field_validator("stems")(_all_stems)


class PresetUpdate(BaseModel):
    """Só os campos enviados mudam (editar, atualizar o mix, mostrar/esconder).

    `icon` e `color` enviados como `null` removem a marca; omitidos, ficam como estão.
    """

    model_config = ConfigDict(extra="forbid")

    name: PresetName | None = None
    stems: dict[Stem, PresetStem] | None = None
    visible: bool | None = None
    icon: PresetIcon | None = None
    color: PresetColor | None = None

    @field_validator("stems")
    @classmethod
    def _stems(cls, value: dict[Stem, PresetStem] | None) -> dict[Stem, PresetStem] | None:
        return None if value is None else _all_stems(value)


class PresetOrder(BaseModel):
    """Todos os ids, na nova ordem."""

    model_config = ConfigDict(extra="forbid")

    ids: list[uuid.UUID]


class PresetOut(BaseModel):
    id: uuid.UUID
    name: str
    position: int
    visible: bool
    stems: dict[Stem, PresetStem]
    icon: PresetIcon | None
    color: PresetColor | None


class PresetListOut(BaseModel):
    # Na ordem do usuário.
    items: list[PresetOut]
