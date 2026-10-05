"""Exports do mix: pedir (vira job no worker leve), listar e baixar."""

import logging
import uuid
from pathlib import Path

from sqlalchemy import select

from app.db.models import ExportModel, JobModel, SessionModel
from app.domain.enums import STEMS, ExportState, JobKind, JobState, MixPreset, SessionState
from app.domain.errors import ConflictError, NotFoundError
from app.pipeline.audio import active_stems, no_active_stems
from app.pipeline.queue import JobRunner
from app.schemas.exports import ExportCreate, ExportOut
from app.services.events import EventPublisher, build_export_out
from app.services.mix import MixService
from app.services.sessions import SessionService
from app.storage import Storage

logger = logging.getLogger(__name__)


class ExportService:
    def __init__(
        self,
        sessions: SessionService,
        mix: MixService,
        events: EventPublisher,
        runner: JobRunner,
        storage: Storage,
    ) -> None:
        self.sessions = sessions
        self.db = sessions.db
        self.mix = mix
        self.events = events
        self.runner = runner
        self.storage = storage

    def create(self, session_id: uuid.UUID, data: ExportCreate) -> ExportOut:
        session = self.sessions.get(session_id)
        if session.state is not SessionState.READY or not session.stems:
            raise ConflictError(
                "session_not_ready", "A sessão ainda não está pronta para exportar."
            )
        preset: MixPreset | None = data.preset
        if data.stems is None:
            saved = self.mix.get(session_id)
            levels, preset = saved.stems, preset or saved.preset
        else:
            levels = data.stems
        available = {stem for stem in STEMS if stem.value in session.stems}
        if not active_stems(levels, available=available):
            raise no_active_stems()

        export = ExportModel(
            session_id=session_id,
            format=data.format,
            preset=preset,
            levels={stem.value: levels[stem].model_dump() for stem in STEMS},
            state=ExportState.QUEUED,
        )
        self.db.add(export)
        self.db.flush()
        job = JobModel(
            kind=JobKind.EXPORT, session_id=session_id, export_id=export.id, state=JobState.QUEUED
        )
        self.db.add(job)
        self.db.flush()
        self.sessions.log_event(
            session_id,
            "export_requested",
            {"export_id": str(export.id), "format": data.format.value},
        )
        self.db.commit()
        self.runner.wake()
        logger.info("Export %s (%s) da sessão %s na fila", export.id, data.format, session.code)
        self.events.export_updated(export.id)
        self.events.jobs_changed(job.id)
        return self.get(export.id)

    def list(self, session_id: uuid.UUID) -> list[ExportOut]:
        session = self.sessions.get(session_id)
        exports = self.db.scalars(
            select(ExportModel)
            .where(ExportModel.session_id == session_id)
            .order_by(ExportModel.created_at.desc(), ExportModel.id)
        ).all()
        return [build_export_out(export, session) for export in exports]

    def get(self, export_id: uuid.UUID) -> ExportOut:
        return build_export_out(*self._get_row(export_id))

    def file(self, export_id: uuid.UUID) -> tuple[Path, str]:
        """Arquivo pronto e o nome de download."""
        export, session = self._get_row(export_id)
        if export.state is not ExportState.DONE or not export.path:
            raise ConflictError("export_not_ready", "Este export ainda não terminou.")
        path = self.storage.resolve(export.path)
        if not path.is_file():
            raise NotFoundError("export_file_missing", "O arquivo deste export não existe mais.")
        return path, build_export_out(export, session).file_name

    def _get_row(self, export_id: uuid.UUID) -> tuple[ExportModel, SessionModel]:
        row = self.db.execute(
            select(ExportModel, SessionModel)
            .join(SessionModel, SessionModel.id == ExportModel.session_id)
            .where(ExportModel.id == export_id)
        ).first()
        if row is None:
            raise NotFoundError("export_not_found", "Export não encontrado.")
        export, session = row
        return export, session
