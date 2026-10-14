"""Uso de disco do `STORAGE_ROOT`, por categoria (stems, exports, backups)."""

import shutil
from pathlib import Path

from app.schemas.disk import DiskUsageOut
from app.services.retention import BACKUP_PATTERN
from app.storage import BACKUPS_DIR, SESSIONS_DIR, Storage


class DiskUsageService:
    def __init__(self, storage: Storage, exports_keep: int, backups_keep: int) -> None:
        self.storage = storage
        self.exports_keep = exports_keep
        self.backups_keep = backups_keep

    def usage(self) -> DiskUsageOut:
        root = self.storage.root
        volume = shutil.disk_usage(root)
        sessions = root / SESSIONS_DIR
        session_dirs = [d for d in sessions.iterdir() if d.is_dir()] if sessions.is_dir() else []
        backups = root / BACKUPS_DIR
        return DiskUsageOut(
            total_bytes=volume.total,
            free_bytes=volume.free,
            stems_bytes=sum(_size(d / "stems") for d in session_dirs),
            exports_bytes=sum(_size(d / "exports") for d in session_dirs),
            backups_bytes=_size(backups, BACKUP_PATTERN),
            exports_keep=self.exports_keep,
            backups_keep=self.backups_keep,
        )


def _size(folder: Path, pattern: str = "*") -> int:
    if not folder.is_dir():
        return 0
    total = 0
    for file in folder.rglob(pattern):
        try:
            if file.is_file():
                total += file.stat().st_size
        except OSError:  # sumiu entre a listagem e o stat
            continue
    return total
