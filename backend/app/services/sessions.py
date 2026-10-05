"""Regras de negócio das sessões: rascunho, listagem, identidade e exclusão."""

import logging
import shutil
import uuid
from typing import Any

from sqlalchemy import ColumnElement, func, select, update
from sqlalchemy.orm import Session

from app.db.engine import TEXT_COLLATION
from app.db.models import CounterModel, JobModel, SessionEventModel, SessionModel
from app.domain.enums import ACTIVE_JOB_STATES, SessionSort, SessionState
from app.domain.errors import ConflictError, session_not_found
from app.domain.text import normalize_artist, search_tokens
from app.schemas.sessions import SessionCreate, SessionPatch
from app.storage import Storage

logger = logging.getLogger(__name__)

SESSION_CODE_COUNTER = "session_code"
TRASH_DIR = ".trash"


def format_session_code(value: int) -> str:
    return f"ST-{value:03d}"


class SessionService:
    def __init__(self, db: Session, storage: Storage) -> None:
        self.db = db
        self.storage = storage

    # --- leitura -----------------------------------------------------------

    def get(self, session_id: uuid.UUID) -> SessionModel:
        session = self.db.get(SessionModel, session_id)
        if session is None:
            raise session_not_found()
        return session

    def list(
        self,
        *,
        q: str | None = None,
        states: list[SessionState] | None = None,
        sort: SessionSort = SessionSort.NEWEST,
        limit: int = 30,
        offset: int = 0,
    ) -> tuple[list[SessionModel], int, dict[SessionState, int]]:
        search = [SessionModel.search_key.contains(t) for t in search_tokens(q).split()]
        filters = [*search, SessionModel.state.in_(states)] if states else search

        count_rows = self.db.execute(
            select(SessionModel.state, func.count()).where(*search).group_by(SessionModel.state)
        ).all()
        counts = dict.fromkeys(SessionState, 0)
        counts.update({state: n for state, n in count_rows})

        total = self.db.scalar(select(func.count()).select_from(SessionModel).where(*filters))
        items = self.db.scalars(
            select(SessionModel)
            .where(*filters)
            .order_by(*_order_by(sort), SessionModel.created_at.desc(), SessionModel.id)
            .limit(limit)
            .offset(offset)
        ).all()
        return list(items), total or 0, counts

    # --- escrita -----------------------------------------------------------

    def create_draft(self, data: SessionCreate) -> SessionModel:
        code = format_session_code(self._next_counter(SESSION_CODE_COUNTER))
        session = SessionModel(
            code=code,
            source_url=str(data.source_url),
            source_title=data.source_title,
            source_channel=data.source_channel,
            thumbnail_url=str(data.thumbnail_url) if data.thumbnail_url else None,
            duration_s=data.duration_s,
            artist=data.artist,
            title=data.title,
            state=SessionState.DRAFT,
        )
        _refresh_keys(session)
        self.db.add(session)
        self.db.flush()
        self._event(session.id, "created", {"code": code})
        self.db.commit()
        logger.info("Sessão %s criada (%s)", code, session.id)
        return session

    def update_identity(self, session_id: uuid.UUID, patch: SessionPatch) -> SessionModel:
        session = self.get(session_id)
        before = {"artist": session.artist, "title": session.title}
        if patch.artist is not None:
            session.artist = patch.artist
        if patch.title is not None:
            session.title = patch.title
        after = {"artist": session.artist, "title": session.title}
        if after != before:
            _refresh_keys(session)
            self._event(session.id, "identity_updated", {"before": before, "after": after})
        self.db.commit()
        return session

    def delete(self, session_id: uuid.UUID) -> None:
        """Exclui a sessão, suas linhas dependentes (cascade) e a pasta no disco.

        A pasta é movida para a lixeira antes do commit: se o commit falhar ela volta,
        e só é apagada de vez depois que o banco confirmou a exclusão.
        """
        session = self.get(session_id)
        if self._has_active_job(session_id):
            raise ConflictError(
                "session_busy",
                "Esta sessão está sendo processada. Cancele o processamento antes de excluir.",
            )

        folder = self.storage.resolve(self.storage.session_dir(session_id))
        trash = self.storage.resolve(f"{TRASH_DIR}/{session_id}")
        moved = False
        if folder.exists():
            trash.parent.mkdir(parents=True, exist_ok=True)
            if trash.exists():
                shutil.rmtree(trash)
            try:
                folder.rename(trash)
            except OSError as exc:
                raise ConflictError(
                    "session_files_in_use",
                    "Não foi possível remover os arquivos da sessão (estão em uso). Tente de novo.",
                ) from exc
            moved = True

        try:
            self.db.delete(session)
            self.db.commit()
        except Exception:
            self.db.rollback()
            if moved:
                try:
                    trash.rename(folder)
                except OSError:
                    # Não mascara o erro original do banco; os arquivos ficam na lixeira.
                    logger.exception(
                        "Não deu para devolver os arquivos da sessão %s de %s", session.code, trash
                    )
            raise

        if moved:
            shutil.rmtree(trash, ignore_errors=True)
            if trash.exists():
                logger.warning("Sobrou lixo da sessão %s em %s", session.code, trash)
        logger.info("Sessão %s excluída", session.code)

    # --- internos ----------------------------------------------------------

    def _has_active_job(self, session_id: uuid.UUID) -> bool:
        return (
            self.db.scalar(
                select(JobModel.id)
                .where(JobModel.session_id == session_id, JobModel.state.in_(ACTIVE_JOB_STATES))
                .limit(1)
            )
            is not None
        )

    def _next_counter(self, name: str) -> int:
        value = self.db.scalar(
            update(CounterModel)
            .where(CounterModel.name == name)
            .values(value=CounterModel.value + 1)
            .returning(CounterModel.value)
        )
        if value is None:
            # A baseline semeia o contador; isto é só uma rede de segurança.
            self.db.add(CounterModel(name=name, value=1))
            self.db.flush()
            value = 1
        return value

    def _event(self, session_id: uuid.UUID, type_: str, payload: dict[str, Any]) -> None:
        self.db.add(SessionEventModel(session_id=session_id, type=type_, payload=payload))


def _refresh_keys(session: SessionModel) -> None:
    session.artist_key = normalize_artist(session.artist)
    session.search_key = search_tokens(
        " ".join(
            part
            for part in (
                session.code,
                session.artist,
                session.title,
                session.source_title,
                session.source_channel,
            )
            if part
        )
    )


def _order_by(sort: SessionSort) -> list[ColumnElement[Any]]:
    match sort:
        case SessionSort.NEWEST:
            return [SessionModel.created_at.desc()]
        case SessionSort.OLDEST:
            return [SessionModel.created_at.asc()]
        case SessionSort.TITLE:
            return [SessionModel.title.collate(TEXT_COLLATION).asc()]
        case SessionSort.ARTIST:
            return [
                SessionModel.artist.collate(TEXT_COLLATION).asc(),
                SessionModel.title.collate(TEXT_COLLATION).asc(),
            ]
        case SessionSort.LONGEST:
            return [SessionModel.duration_s.desc().nulls_last()]
        case SessionSort.SHORTEST:
            return [SessionModel.duration_s.asc().nulls_last()]
