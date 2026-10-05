import uuid
from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import update

from app.cli import main
from app.config import Settings, get_settings
from app.db.models import ExportModel, JobModel, SessionModel
from app.domain.enums import ExportFormat, JobState, SessionState
from app.storage import Storage
from tests.conftest import create_session, open_db


def touch(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * 10)
    return path


@pytest.fixture
def layout(client: TestClient, migrated: Settings) -> dict[str, Path]:
    """Uma sessão pronta com sobras + uma pasta órfã + lixeira."""
    root = migrated.storage_root
    session_id = uuid.UUID(str(create_session(client)["id"]))
    with open_db(client) as db:
        db.execute(
            update(SessionModel)
            .where(SessionModel.id == session_id)
            .values(state=SessionState.READY, stems={"vocals": "x"})
        )
        export = ExportModel(
            session_id=session_id,
            format=ExportFormat.WAV,
            levels={},
            path=Storage.export_file(session_id, uuid.uuid4(), "wav"),
        )
        db.add(export)
        db.commit()
        kept_export = root / str(export.path)
    return {
        "stem": touch(root / Storage.stem_audio(session_id, "vocals")),
        "kept_export": touch(kept_export),
        "orphan_export": touch(root / Storage.export_file(session_id, uuid.uuid4(), "mp3")),
        "raw": touch(root / Storage.raw_dir(session_id) / "source.webm").parent,
        "work": touch(root / Storage.work_dir(session_id) / "a.wav").parent,
        "orphan_session": touch(root / Storage.stems_dir(uuid.uuid4()) / "vocals.mp3").parents[1],
        "not_uuid": touch(root / "sessions" / "lixo" / "a.txt").parent,
        "trash": touch(root / ".trash" / "x" / "a.mp3").parents[1],
    }


@pytest.fixture
def cli_env(monkeypatch: pytest.MonkeyPatch, migrated: Settings) -> Iterator[None]:
    monkeypatch.setenv("STORAGE_ROOT", str(migrated.storage_root))
    monkeypatch.setenv("DATABASE_URL", migrated.database_url)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_cleanup_remove_so_os_orfaos(layout: dict[str, Path], cli_env: None) -> None:
    assert main(["cleanup", "--min-age-minutes", "0"]) == 0

    for kept in ("stem", "kept_export"):
        assert layout[kept].exists(), kept
    for removed in ("orphan_export", "raw", "work", "orphan_session", "not_uuid", "trash"):
        assert not layout[removed].exists(), removed


def test_cleanup_dry_run_nao_apaga(layout: dict[str, Path], cli_env: None) -> None:
    assert main(["cleanup", "--dry-run", "--min-age-minutes", "0"]) == 0

    assert all(path.exists() for path in layout.values())


def test_cleanup_poupa_sessao_com_job_ativo(
    client: TestClient, migrated: Settings, cli_env: None
) -> None:
    session = create_session(client)
    client.post(f"/api/sessions/{session['id']}/process")
    # O fixture `client` não tem handlers: o job falha rápido. Recoloca como ativo.
    session_id = uuid.UUID(str(session["id"]))
    with open_db(client) as db:
        client.app.state.job_runner.stop()  # type: ignore[attr-defined]
        db.execute(
            update(JobModel).where(JobModel.session_id == session_id).values(state=JobState.QUEUED)
        )
        db.commit()
    raw = touch(migrated.storage_root / Storage.raw_dir(session_id) / "source.webm")

    main(["cleanup", "--min-age-minutes", "0"])

    assert raw.exists()


def test_cleanup_poupa_o_que_e_recente(layout: dict[str, Path], cli_env: None) -> None:
    # Com o padrão (60 min), nada recém-criado sai: pode ser de um job que começou agora.
    assert main(["cleanup"]) == 0

    assert all(path.exists() for path in layout.values())
