from importlib.metadata import version

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def test_health_com_tudo_disponivel(monkeypatch: pytest.MonkeyPatch, migrated: Settings) -> None:
    monkeypatch.setattr("app.services.health.shutil.which", lambda name: f"/bin/{name}")

    with TestClient(create_app(migrated)) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "version": version("stemma"),
        "db": "ok",
        "ffmpeg": "ok",
        "js_runtime": "ok",
        "gpu": "unknown",
    }


def test_health_acusa_binarios_ausentes(
    monkeypatch: pytest.MonkeyPatch, migrated: Settings
) -> None:
    monkeypatch.setattr("app.services.health.shutil.which", lambda name: None)
    settings = migrated.model_copy(update={"ffmpeg_bin": "ffmpeg-x", "ytdlp_js_runtime": "deno-x"})

    with TestClient(create_app(settings)) as client:
        body = client.get("/health").json()

    assert body["ffmpeg"] == "missing"
    assert body["js_runtime"] == "missing"
    # Binário ausente não derruba o app: só o banco define o status.
    assert body["status"] == "ok"


def test_health_degradado_sem_banco(settings: Settings) -> None:
    # Diretório no lugar do arquivo do banco: o SQLite não consegue abrir.
    settings.storage_root.mkdir(parents=True)
    (settings.storage_root / "stemma.db").mkdir()

    with TestClient(create_app(settings)) as client:
        body = client.get("/health").json()

    assert body["db"] == "error"
    assert body["status"] == "degraded"
