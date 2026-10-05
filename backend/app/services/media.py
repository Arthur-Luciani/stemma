"""Arquivos de uma sessão pronta servidos ao player: MP3 dos stems e peaks da waveform."""

import uuid
from pathlib import Path

from app.domain.enums import Stem
from app.domain.errors import NotFoundError
from app.services.sessions import SessionService
from app.storage import Storage


class MediaService:
    def __init__(self, sessions: SessionService, storage: Storage) -> None:
        self.sessions = sessions
        self.storage = storage

    def stem_audio(self, session_id: uuid.UUID, stem: Stem) -> Path:
        rel = self._stems(session_id).get(stem.value)
        if rel is None:
            raise _stem_not_found()
        return self._existing(rel)

    def stem_peaks(self, session_id: uuid.UUID, stem: Stem) -> Path:
        if stem.value not in self._stems(session_id):
            raise _stem_not_found()
        return self._existing(Storage.stem_peaks(session_id, stem.value))

    def _stems(self, session_id: uuid.UUID) -> dict[str, str]:
        return dict(self.sessions.get(session_id).stems or {})

    def _existing(self, rel: str) -> Path:
        path = self.storage.resolve(rel)
        if not path.is_file():
            raise _stem_not_found()
        return path


def _stem_not_found() -> NotFoundError:
    return NotFoundError("stem_not_found", "Este stem não existe nesta sessão.")
