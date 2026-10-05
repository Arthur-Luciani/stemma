"""Limpeza de arquivos órfãos no `STORAGE_ROOT` (CLI `python -m app.cli cleanup`).

Remove o que nenhuma linha do banco referencia: pastas de sessões excluídas, a lixeira,
sobras de processamento (`raw/`, `work/`) de sessões paradas, stems de sessões que não
estão prontas e arquivos de export sem registro.
"""

import logging
import shutil
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import ExportModel, JobModel, SessionModel
from app.domain.enums import ACTIVE_JOB_STATES, SessionState
from app.services.sessions import TRASH_DIR
from app.storage import SESSIONS_DIR, Storage

logger = logging.getLogger(__name__)


@dataclass
class CleanupReport:
    removed: list[str] = field(default_factory=list)
    freed_bytes: int = 0


class CleanupService:
    def __init__(self, db: Session, storage: Storage) -> None:
        self.db = db
        self.storage = storage

    def run(self, *, dry_run: bool = False) -> CleanupReport:
        report = CleanupReport()
        sessions = {
            s.id: s.state
            for s in self.db.execute(select(SessionModel.id, SessionModel.state)).all()
        }
        busy = set(
            self.db.scalars(
                select(JobModel.session_id).where(JobModel.state.in_(ACTIVE_JOB_STATES))
            ).all()
        )
        export_paths = {p for p in self.db.scalars(select(ExportModel.path)).all() if p is not None}

        trash = self.storage.root / TRASH_DIR
        if trash.exists():
            self._remove(trash, report, dry_run)

        root = self.storage.root / SESSIONS_DIR
        for folder in sorted(root.iterdir()) if root.exists() else []:
            session_id = _parse_uuid(folder.name)
            if session_id is None or session_id not in sessions:
                self._remove(folder, report, dry_run)
                continue
            if session_id in busy:
                continue
            leftovers = [Storage.raw_dir(session_id), Storage.work_dir(session_id)]
            if sessions[session_id] is not SessionState.READY:
                leftovers.append(Storage.stems_dir(session_id))
            for rel in leftovers:
                path = self.storage.resolve(rel)
                if path.exists():
                    self._remove(path, report, dry_run)
            exports = self.storage.resolve(Storage.exports_dir(session_id))
            for file in sorted(exports.iterdir()) if exports.exists() else []:
                if self.storage.relative(file) not in export_paths:
                    self._remove(file, report, dry_run)
        return report

    def _remove(self, path: Path, report: CleanupReport, dry_run: bool) -> None:
        size = _size(path)
        report.removed.append(self.storage.relative(path))
        report.freed_bytes += size
        if dry_run:
            return
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
        else:
            path.unlink(missing_ok=True)
        logger.info("Removido: %s (%d bytes)", path, size)


def _parse_uuid(text: str) -> uuid.UUID | None:
    try:
        return uuid.UUID(text)
    except ValueError:
        return None


def _size(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
