from collections.abc import Iterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.config import BACKEND_DIR, Settings
from app.main import create_app


def alembic_config(database_url: str) -> Config:
    config = Config(BACKEND_DIR / "alembic.ini")
    config.attributes["database_url"] = database_url
    config.attributes["skip_logging_config"] = True
    return config


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
    with TestClient(create_app(migrated)) as test_client:
        yield test_client


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
