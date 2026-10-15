"""Presets de mix do usuário: perfis globais de volume/pan/mute por stem (ADR 0018)."""

import logging
import uuid
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import MixPresetModel
from app.domain.enums import STEMS, Stem
from app.domain.errors import ConflictError, InvalidInputError, NotFoundError
from app.schemas.presets import PresetCreate, PresetOrder, PresetOut, PresetStem, PresetUpdate

logger = logging.getLogger(__name__)


def _name_taken() -> ConflictError:
    return ConflictError("preset_name_taken", "Já existe um preset com esse nome.")


class PresetService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def list_all(self) -> list[PresetOut]:
        rows = self.db.scalars(
            select(MixPresetModel).order_by(MixPresetModel.position, MixPresetModel.name)
        ).all()
        return [PresetOut.model_validate(_out(row)) for row in rows]

    def create(self, data: PresetCreate) -> PresetOut:
        name = data.name.strip()
        self._ensure_name_free(name)
        last = self.db.scalar(select(func.max(MixPresetModel.position)))
        row = MixPresetModel(
            name=name,
            position=0 if last is None else last + 1,
            visible=data.visible,
            stems=_stems_json(data.stems),
        )
        self.db.add(row)
        self.db.commit()
        logger.info("Preset %r criado", name)
        return PresetOut.model_validate(_out(row))

    def update(self, preset_id: uuid.UUID, data: PresetUpdate) -> PresetOut:
        row = self._get_row(preset_id)
        if data.name is not None:
            name = data.name.strip()
            self._ensure_name_free(name, except_id=preset_id)
            row.name = name
        if data.stems is not None:
            row.stems = _stems_json(data.stems)
        if data.visible is not None:
            row.visible = data.visible
        self.db.commit()
        return PresetOut.model_validate(_out(row))

    def delete(self, preset_id: uuid.UUID) -> None:
        row = self._get_row(preset_id)
        self.db.delete(row)
        self.db.commit()
        logger.info("Preset %r excluído", row.name)

    def reorder(self, data: PresetOrder) -> list[PresetOut]:
        rows = {row.id: row for row in self.db.scalars(select(MixPresetModel))}
        if len(data.ids) != len(set(data.ids)) or set(data.ids) != set(rows):
            raise InvalidInputError(
                "preset_order_invalid", "A ordem precisa listar todos os presets, uma vez cada."
            )
        for position, preset_id in enumerate(data.ids):
            rows[preset_id].position = position
        self.db.commit()
        return self.list_all()

    def _get_row(self, preset_id: uuid.UUID) -> MixPresetModel:
        row = self.db.get(MixPresetModel, preset_id)
        if row is None:
            raise NotFoundError("preset_not_found", "Preset não encontrado.")
        return row

    def _ensure_name_free(self, name: str, except_id: uuid.UUID | None = None) -> None:
        # Sem diferenciar caixa: "bateria baixa" e "Bateria baixa" confundiriam no seletor.
        query = select(MixPresetModel.id).where(func.lower(MixPresetModel.name) == name.lower())
        if except_id is not None:
            query = query.where(MixPresetModel.id != except_id)
        if self.db.scalar(query) is not None:
            raise _name_taken()


def _stems_json(stems: dict[Stem, PresetStem]) -> dict[str, Any]:
    return {stem.value: stems[stem].model_dump() for stem in STEMS}


def _out(row: MixPresetModel) -> dict[str, object]:
    return {
        "id": row.id,
        "name": row.name,
        "position": row.position,
        "visible": row.visible,
        "stems": row.stems,
    }
