import sys
from importlib.metadata import version

import pytest
from fastapi.testclient import TestClient
from yt_dlp.version import __version__ as ytdlp_version

from app.config import Settings
from app.main import create_app
from app.pipeline.probe import GpuProbe


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
        "ytdlp": ytdlp_version,
    }


def test_health_acusa_binarios_ausentes(
    monkeypatch: pytest.MonkeyPatch, migrated: Settings
) -> None:
    monkeypatch.setattr("app.services.health.shutil.which", lambda name: None)
    settings = migrated.model_copy(
        update={"ffmpeg_bin": "ffmpeg-x", "ytdlp_js_runtime": ["deno-x", "node-x"]}
    )

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


def test_health_acusa_banco_sem_migration(settings: Settings) -> None:
    with TestClient(create_app(settings)) as client:
        body = client.get("/health").json()

    assert body["db"] == "outdated"
    assert body["status"] == "degraded"


def test_runtime_js_basta_um_da_lista(monkeypatch: pytest.MonkeyPatch, migrated: Settings) -> None:
    monkeypatch.setattr(
        "app.services.health.shutil.which", lambda name: "/bin/node" if name == "node" else None
    )

    with TestClient(create_app(migrated)) as client:
        assert client.get("/health").json()["js_runtime"] == "ok"


def test_sonda_da_gpu() -> None:
    assert GpuProbe([sys.executable, "-c", "print('cuda')"]).run_now() == "ok"
    assert GpuProbe([sys.executable, "-c", "print('cpu')"]).run_now() == "unavailable"
    assert GpuProbe([sys.executable, "-c", "import sys; sys.exit(1)"]).run_now() == "unavailable"
    assert GpuProbe(["python-que-nao-existe"]).run_now() == "unavailable"
