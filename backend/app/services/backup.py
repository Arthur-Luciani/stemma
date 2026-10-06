"""Cópia consistente do banco SQLite (API de backup do SQLite, segura com WAL).

Usada pelo `deploy/update.ps1` antes das migrations e para restaurar num rollback.
"""

import logging
import sqlite3
from pathlib import Path

from sqlalchemy.engine import make_url

from app.domain.errors import AppError

logger = logging.getLogger(__name__)


def sqlite_path(database_url: str) -> Path:
    url = make_url(database_url)
    if url.get_backend_name() != "sqlite" or not url.database or url.database == ":memory:":
        raise AppError("backup_unsupported", "Backup só funciona com banco SQLite em arquivo.")
    return Path(url.database)


def _copy(src: Path, dest: Path) -> None:
    with sqlite3.connect(src) as source, sqlite3.connect(dest) as target:
        source.backup(target)
    # `with` do sqlite3 só faz commit; fecha de verdade para liberar o arquivo no Windows.
    source.close()
    target.close()


def backup_database(database_url: str, dest: Path) -> Path:
    src = sqlite_path(database_url)
    if not src.is_file():
        raise AppError("backup_no_database", f"Banco não encontrado: {src}")
    if dest.exists():
        raise AppError("backup_exists", f"O destino do backup já existe: {dest}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    _copy(src, dest)
    logger.info("Backup de %s em %s", src, dest)
    return dest


def restore_database(database_url: str, backup: Path) -> Path:
    """Sobrescreve o banco com o backup. Só com o app parado."""
    if not backup.is_file():
        raise AppError("backup_not_found", f"Backup não encontrado: {backup}")
    dest = sqlite_path(database_url)
    dest.parent.mkdir(parents=True, exist_ok=True)
    _copy(backup, dest)
    logger.info("Banco %s restaurado de %s", dest, backup)
    return dest
