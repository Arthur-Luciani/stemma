"""Retenção em disco: quantos backups do banco e exports prontos ficam guardados.

Funções usadas pelo pedido de export (`ExportService`), pelo `cleanup` e pelo fim da
atualização (`prune-backups`). Sempre ficam os mais novos; com `keep >= 1` o backup da última
atualização nunca sai.
"""

import logging
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import ExportModel
from app.domain.enums import ExportState
from app.storage import BACKUPS_DIR, Storage

logger = logging.getLogger(__name__)

# Nome dos backups do banco (`deploy/StemmaDeploy.Flows.ps1`, `New-BackupPath`).
BACKUP_PATTERN = "stemma-*.db"


@dataclass
class PruneReport:
    removed: list[str] = field(default_factory=list)
    freed_bytes: int = 0

    def extend(self, other: "PruneReport") -> None:
        self.removed.extend(other.removed)
        self.freed_bytes += other.freed_bytes


def select_backups_to_prune(files: Iterable[Path], keep: int) -> list[Path]:
    """Backups além dos `keep` mais novos (por data de modificação). Só `stemma-*.db`."""
    backups = [f for f in files if f.is_file() and f.match(BACKUP_PATTERN)]
    backups.sort(key=lambda f: (f.stat().st_mtime, f.name), reverse=True)
    return backups[max(keep, 0) :]


def select_exports_to_prune(exports: Iterable[ExportModel], keep: int) -> list[ExportModel]:
    """Exports prontos além dos `keep` mais recentes. Na fila, rodando ou falhos ficam fora."""
    done = [e for e in exports if e.state is ExportState.DONE]
    done.sort(key=lambda e: (e.created_at, str(e.id)), reverse=True)
    return done[max(keep, 0) :]


def prune_backups(storage: Storage, keep: int, *, dry_run: bool = False) -> PruneReport:
    report = PruneReport()
    folder = storage.root / BACKUPS_DIR
    if not folder.is_dir():
        return report
    for backup in select_backups_to_prune(folder.iterdir(), keep):
        size = backup.stat().st_size
        if not dry_run:
            try:
                backup.unlink()
            except OSError:
                logger.warning("Não deu para apagar o backup %s", backup, exc_info=True)
                continue
            logger.info("Backup antigo removido: %s", backup)
        report.removed.append(storage.relative(backup))
        report.freed_bytes += size
    return report


def prune_exports(
    db: Session, storage: Storage, session_id: object, keep: int, *, dry_run: bool = False
) -> PruneReport:
    """Apaga o arquivo e a linha dos exports prontos além dos `keep` mais recentes da sessão.

    Se o arquivo não puder ser apagado (ex.: em download no Windows), a linha fica e o export
    é tentado de novo na próxima poda."""
    report = PruneReport()
    exports = db.scalars(select(ExportModel).where(ExportModel.session_id == session_id)).all()
    for export in select_exports_to_prune(exports, keep):
        size = 0
        label = f"export {export.id}"
        if export.path:
            path = storage.resolve(export.path)
            label = export.path
            if path.is_file():
                size = path.stat().st_size
                if not dry_run:
                    try:
                        path.unlink()
                    except OSError:
                        logger.warning("Não deu para apagar o export %s", path, exc_info=True)
                        continue
        if not dry_run:
            db.delete(export)
            logger.info("Export antigo removido: %s", label)
        report.removed.append(label)
        report.freed_bytes += size
    if not dry_run and report.removed:
        db.commit()
    return report
