"""Estado do mixer por sessão (volume/pan/mute/solo por stem, preset e loop A–B)."""

import uuid

from sqlalchemy.dialects.sqlite import insert

from app.db.models import MixStateModel
from app.db.types import utcnow
from app.domain.enums import STEMS, MixPreset
from app.domain.errors import InvalidInputError
from app.schemas.mix import MixStateIn, MixStateOut, StemMix
from app.services.sessions import SessionService


def default_mix() -> MixStateOut:
    return MixStateOut(
        stems={stem: StemMix() for stem in STEMS},
        preset=MixPreset.ORIGINAL,
        updated_at=None,
    )


class MixService:
    def __init__(self, sessions: SessionService) -> None:
        self.sessions = sessions
        self.db = sessions.db

    def get(self, session_id: uuid.UUID) -> MixStateOut:
        self.sessions.get(session_id)
        row = self.db.get(MixStateModel, session_id)
        if row is None:
            return default_mix()
        return MixStateOut.model_validate(
            {
                "stems": row.stems,
                "preset": row.preset,
                "loop_a_s": row.loop_a_s,
                "loop_b_s": row.loop_b_s,
                "updated_at": row.updated_at,
            }
        )

    def save(self, session_id: uuid.UUID, data: MixStateIn) -> MixStateOut:
        session = self.sessions.get(session_id)
        if (
            data.loop_b_s is not None
            and session.duration_s is not None
            and data.loop_b_s > session.duration_s
        ):
            raise InvalidInputError("loop_out_of_range", "O loop A–B passa do fim da música.")

        values = {
            "stems": {stem.value: data.stems[stem].model_dump() for stem in STEMS},
            "preset": data.preset,
            "loop_a_s": data.loop_a_s,
            "loop_b_s": data.loop_b_s,
            "updated_at": utcnow(),
        }
        # Upsert atômico: dois saves simultâneos do primeiro mix não colidem na PK.
        stmt = insert(MixStateModel).values(session_id=session_id, **values)
        self.db.execute(
            stmt.on_conflict_do_update(index_elements=[MixStateModel.session_id], set_=values)
        )
        self.db.commit()
        self.db.expire_all()
        return self.get(session_id)
