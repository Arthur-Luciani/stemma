from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


@pytest.fixture
def dist(tmp_path: Path) -> Path:
    root = tmp_path / "dist"
    (root / "assets").mkdir(parents=True)
    (root / "index.html").write_text("<!doctype html><title>Stemma</title>", encoding="utf-8")
    (root / "assets" / "index-abc123.js").write_text("console.log(1)", encoding="utf-8")
    (root / "sw.js").write_text("// sw", encoding="utf-8")
    (root / "manifest.webmanifest").write_text("{}", encoding="utf-8")
    (root / "pwa-192x192.png").write_bytes(b"\x89PNG")
    (tmp_path / "segredo.txt").write_text("fora do dist", encoding="utf-8")
    return root


@pytest.fixture
def spa_client(migrated: Settings, dist: Path) -> Iterator[TestClient]:
    settings = migrated.model_copy(update={"serve_frontend_dir": dist})
    with TestClient(create_app(settings, job_handlers={})) as client:
        yield client


def test_raiz_serve_index_sem_cache(spa_client: TestClient) -> None:
    response = spa_client.get("/")

    assert response.status_code == 200
    assert "<title>Stemma</title>" in response.text
    assert response.headers["cache-control"] == "no-cache"


def test_deep_link_cai_no_index(spa_client: TestClient) -> None:
    response = spa_client.get("/sessions/123/mix?view=ajustar")

    assert response.status_code == 200
    assert "<title>Stemma</title>" in response.text
    assert response.headers["cache-control"] == "no-cache"


def test_asset_com_hash_e_imutavel(spa_client: TestClient) -> None:
    response = spa_client.get("/assets/index-abc123.js")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=31536000, immutable"


@pytest.mark.parametrize("path", ["/sw.js", "/manifest.webmanifest"])
def test_service_worker_e_manifest_sem_cache(spa_client: TestClient, path: str) -> None:
    response = spa_client.get(path)

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-cache"


def test_icone_com_cache_curto(spa_client: TestClient) -> None:
    response = spa_client.get("/pwa-192x192.png")

    assert response.headers["cache-control"] == "public, max-age=86400"


def test_head_funciona(spa_client: TestClient) -> None:
    assert spa_client.head("/").status_code == 200


@pytest.mark.parametrize("path", ["/api/nao-existe", "/health/x", "/ws"])
def test_prefixos_do_backend_nao_caem_no_fallback(spa_client: TestClient, path: str) -> None:
    response = spa_client.get(path)

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_api_continua_respondendo(spa_client: TestClient) -> None:
    assert spa_client.get("/api/sessions").status_code == 200
    assert spa_client.get("/health").json()["status"] in {"ok", "degraded"}


@pytest.mark.parametrize("path", ["/..%2Fsegredo.txt", "/assets/..%2F..%2Fsegredo.txt"])
def test_path_fora_do_dist_nao_e_servido(spa_client: TestClient, path: str) -> None:
    response = spa_client.get(path)

    assert "fora do dist" not in response.text


def test_sem_config_nao_serve_frontend(client: TestClient) -> None:
    assert client.get("/").status_code == 404


def test_dist_sem_index_nao_registra_rota(migrated: Settings, tmp_path: Path) -> None:
    settings = migrated.model_copy(update={"serve_frontend_dir": tmp_path / "vazio"})
    with TestClient(create_app(settings, job_handlers={})) as client:
        assert client.get("/").status_code == 404


def test_serve_frontend_dir_relativo_resolve_do_repo(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.config import REPO_DIR

    monkeypatch.setenv("SERVE_FRONTEND_DIR", "frontend/dist")

    assert Settings(_env_file=None).serve_frontend_dir == (REPO_DIR / "frontend" / "dist").resolve()


def test_serve_frontend_dir_vazio_e_none(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SERVE_FRONTEND_DIR", "")

    assert Settings(_env_file=None).serve_frontend_dir is None
