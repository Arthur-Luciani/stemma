import uuid
from pathlib import Path

import pytest

from app.domain.errors import AppError
from app.storage import Storage


def test_resolve_dentro_da_raiz(tmp_path: Path) -> None:
    storage = Storage(tmp_path)

    assert (
        storage.resolve("sessions/abc/vocals.mp3") == tmp_path.resolve() / "sessions/abc/vocals.mp3"
    )


@pytest.mark.parametrize(
    "rel",
    ["../fora.txt", "sessions/../../fora.txt", "/etc/passwd", "C:/Windows", r"a\..\..\b", "", "."],
)
def test_resolve_recusa_paths_fora_da_raiz(tmp_path: Path, rel: str) -> None:
    with pytest.raises(AppError) as exc:
        Storage(tmp_path).resolve(rel)

    assert exc.value.code == "invalid_storage_path"


def test_relative_e_inverso_de_resolve(tmp_path: Path) -> None:
    storage = Storage(tmp_path)

    assert storage.relative(storage.resolve("sessions/x/a.wav")) == "sessions/x/a.wav"
    with pytest.raises(AppError):
        storage.relative(tmp_path.parent / "fora.wav")


def test_session_dir_e_relativo() -> None:
    session_id = uuid.uuid4()

    assert Storage.session_dir(session_id) == f"sessions/{session_id}"
