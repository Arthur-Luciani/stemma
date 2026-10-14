import uuid
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.config import BACKEND_DIR, Settings
from app.db.models import ExportModel, JobModel, SessionModel
from app.domain.enums import ExportFormat, ExportState, JobKind, JobState, SessionState
from app.main import create_app
from app.pipeline.probe import GpuProbe
from app.storage import Storage
from tests.fakes import ControlledHandler


def alembic_config(database_url: str) -> Config:
    config = Config(BACKEND_DIR / "alembic.ini")
    config.attributes["database_url"] = database_url
    config.attributes["skip_logging_config"] = True
    return config


@pytest.fixture(autouse=True)
def _no_gpu_probe(monkeypatch: pytest.MonkeyPatch) -> None:
    """A sonda da GPU importaria o torch num subprocess a cada app de teste."""
    monkeypatch.setattr(GpuProbe, "start", lambda self: None)


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    storage = tmp_path / "storage"
    return Settings(_env_file=None, storage_root=storage, database_url="")


@pytest.fixture
def migrated(settings: Settings) -> Settings:
    """Banco criado pelas migrations (nunca `create_all`)."""
    command.upgrade(alembic_config(settings.database_url), "head")
    return settings


@pytest.fixture
def migrated_storage(migrated: Settings) -> Path:
    return migrated.storage_root


@pytest.fixture
def client(migrated: Settings) -> Iterator[TestClient]:
    # Sem handlers: jobs falham com `pipeline_unavailable` (testes da API sem pipeline).
    with TestClient(create_app(migrated, job_handlers={})) as test_client:
        yield test_client


@pytest.fixture
def handler() -> ControlledHandler:
    return ControlledHandler()


@pytest.fixture
def queue_client(migrated: Settings, handler: ControlledHandler) -> Iterator[TestClient]:
    """App com o `handler` controlável no lugar do pipeline de processamento."""
    with TestClient(create_app(migrated, job_handlers={JobKind.PROCESS: handler})) as test_client:
        yield test_client


def open_db(client: TestClient) -> Session:
    session: Session = client.app.state.sessionmaker()  # type: ignore[attr-defined]
    return session


@pytest.fixture
def db(client: TestClient) -> Iterator[Session]:
    """Sessão direta no mesmo banco do app, para preparar/conferir dados."""
    session: Session = client.app.state.sessionmaker()  # type: ignore[attr-defined]
    try:
        yield session
    finally:
        session.close()


def make_session_payload(**overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "source_url": "https://www.youtube.com/watch?v=abc123",
        "source_title": "Queen - Bohemian Rhapsody (Official Video)",
        "source_channel": "Queen Official",
        "thumbnail_url": "https://i.ytimg.com/vi/abc123/hqdefault.jpg",
        "duration_s": 354.0,
        "artist": "Queen",
        "title": "Bohemian Rhapsody",
    }
    payload.update(overrides)
    return payload


def create_session(client: TestClient, **overrides: object) -> dict[str, object]:
    response = client.post("/api/sessions", json=make_session_payload(**overrides))
    assert response.status_code == 201, response.text
    body: dict[str, object] = response.json()
    return body


def process_session(client: TestClient, **overrides: object) -> dict[str, object]:
    """Cria uma sessão e a põe na fila; devolve o job."""
    session = create_session(client, **overrides)
    response = client.post(f"/api/sessions/{session['id']}/process")
    assert response.status_code == 201, response.text
    body: dict[str, object] = response.json()
    return body


def job_row(client: TestClient, job_id: object) -> JobModel:
    with open_db(client) as db:
        job = db.get(JobModel, uuid.UUID(str(job_id)))
        assert job is not None
        return job


def session_row(client: TestClient, session_id: object) -> SessionModel:
    with open_db(client) as db:
        session = db.get(SessionModel, uuid.UUID(str(session_id)))
        assert session is not None
        return session


def job_state(client: TestClient, job_id: object) -> JobState:
    return job_row(client, job_id).state


def ready_session_row(client: TestClient) -> uuid.UUID:
    """Sessão pronta (com stems no banco) sem passar pelo pipeline."""
    session_id = uuid.UUID(str(create_session(client)["id"]))
    with open_db(client) as db:
        db.execute(
            update(SessionModel)
            .where(SessionModel.id == session_id)
            .values(state=SessionState.READY, stems={"vocals": "x"})
        )
        db.commit()
    return session_id


def add_export(
    client: TestClient,
    root: Path,
    session_id: uuid.UUID,
    *,
    age_min: int,
    state: ExportState = ExportState.DONE,
    size: int = 10,
) -> ExportModel:
    """Export com `age_min` minutos de idade e, se pronto, o arquivo no disco."""
    export_id = uuid.uuid4()
    rel = Storage.export_file(session_id, export_id, "mp3")
    done = state is ExportState.DONE
    with open_db(client) as db:
        export = ExportModel(
            id=export_id,
            session_id=session_id,
            format=ExportFormat.MP3,
            levels={},
            state=state,
            path=rel if done else None,
            size_bytes=size if done else None,
            created_at=datetime.now(UTC) - timedelta(minutes=age_min),
        )
        db.add(export)
        db.commit()
        db.refresh(export)
        db.expunge(export)
    if done:
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"x" * size)
    return export


def export_ids(client: TestClient, session_id: uuid.UUID) -> list[uuid.UUID]:
    with open_db(client) as db:
        return list(
            db.scalars(
                select(ExportModel.id)
                .where(ExportModel.session_id == session_id)
                .order_by(ExportModel.created_at.desc())
            )
        )
