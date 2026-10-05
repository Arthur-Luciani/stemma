"""Helper único de paths do `STORAGE_ROOT`.

O banco guarda só paths **relativos** (POSIX) ao `STORAGE_ROOT`; tudo que vira path absoluto
passa por `Storage.resolve`, que também garante que o resultado não escapa da raiz.
"""

import uuid
from pathlib import Path, PurePosixPath

from app.domain.errors import AppError

SESSIONS_DIR = "sessions"


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

    # --- layout de uma sessão (ADR 0010); tudo relativo ao STORAGE_ROOT -----------

    @staticmethod
    def session_dir(session_id: uuid.UUID) -> str:
        return f"{SESSIONS_DIR}/{session_id}"

    @classmethod
    def raw_dir(cls, session_id: uuid.UUID) -> str:
        """Áudio baixado; apagado ao fim do processamento."""
        return f"{cls.session_dir(session_id)}/raw"

    @classmethod
    def work_dir(cls, session_id: uuid.UUID) -> str:
        """Saída temporária do Demucs (WAVs); apagada ao fim do processamento."""
        return f"{cls.session_dir(session_id)}/work"

    @classmethod
    def stems_dir(cls, session_id: uuid.UUID) -> str:
        return f"{cls.session_dir(session_id)}/stems"

    @classmethod
    def stem_audio(cls, session_id: uuid.UUID, stem: str) -> str:
        return f"{cls.stems_dir(session_id)}/{stem}.mp3"

    @classmethod
    def stem_peaks(cls, session_id: uuid.UUID, stem: str) -> str:
        return f"{cls.stems_dir(session_id)}/{stem}.peaks.json"

    @classmethod
    def exports_dir(cls, session_id: uuid.UUID) -> str:
        return f"{cls.session_dir(session_id)}/exports"

    @classmethod
    def export_file(cls, session_id: uuid.UUID, export_id: uuid.UUID, ext: str) -> str:
        return f"{cls.exports_dir(session_id)}/{export_id}.{ext}"


def _invalid_path(rel: object) -> AppError:
    return AppError("invalid_storage_path", f"Caminho fora da pasta de dados: {rel}", 500)
