"""Helper único de paths do `STORAGE_ROOT`.

O banco guarda só paths **relativos** (POSIX) ao `STORAGE_ROOT`; tudo que vira path absoluto
passa por `Storage.resolve`, que também garante que o resultado não escapa da raiz.
"""

import uuid
from pathlib import Path, PurePosixPath

from app.domain.errors import AppError


class Storage:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()

    def resolve(self, rel: str | PurePosixPath) -> Path:
        rel_path = PurePosixPath(rel)
        if rel_path.is_absolute() or ":" in str(rel_path) or "\\" in str(rel_path):
            raise _invalid_path(rel)
        path = (self.root / rel_path).resolve()
        if path == self.root or not path.is_relative_to(self.root):
            raise _invalid_path(rel)
        return path

    def relative(self, path: Path) -> str:
        """Inverso de `resolve`: path absoluto dentro da raiz → string relativa POSIX."""
        resolved = path.resolve()
        if resolved == self.root or not resolved.is_relative_to(self.root):
            raise _invalid_path(str(path))
        return resolved.relative_to(self.root).as_posix()

    @staticmethod
    def session_dir(session_id: uuid.UUID) -> str:
        return f"sessions/{session_id}"


def _invalid_path(rel: object) -> AppError:
    return AppError("invalid_storage_path", f"Caminho fora da pasta de dados: {rel}", 500)
