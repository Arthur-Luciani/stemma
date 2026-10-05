from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.domain.enums import MixPreset, Stem


class StemMix(BaseModel):
    model_config = ConfigDict(extra="forbid")

    volume: Annotated[float, Field(ge=0, le=100)] = 100
    pan: Annotated[float, Field(ge=-1, le=1)] = 0
    mute: bool = False
    solo: bool = False


class MixStateIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    stems: dict[Stem, StemMix]
    preset: MixPreset
    loop_a_s: Annotated[float, Field(ge=0)] | None = None
    loop_b_s: Annotated[float, Field(ge=0)] | None = None

    @field_validator("stems")
    @classmethod
    def _all_stems(cls, value: dict[Stem, StemMix]) -> dict[Stem, StemMix]:
        missing = [s.value for s in Stem if s not in value]
        if missing:
            raise ValueError(f"faltam os stems: {', '.join(missing)}")
        return value

    @model_validator(mode="after")
    def _loop(self) -> "MixStateIn":
        a, b = self.loop_a_s, self.loop_b_s
        if (a is None) != (b is None):
            raise ValueError("o loop precisa dos dois pontos (A e B) ou de nenhum")
        if a is not None and b is not None and a >= b:
            raise ValueError("o ponto A do loop precisa vir antes do B")
        return self


class MixStateOut(MixStateIn):
    # Nulo quando a sessão ainda não tem mix salvo (valores padrão).
    updated_at: datetime | None
