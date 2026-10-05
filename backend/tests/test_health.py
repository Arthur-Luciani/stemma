from importlib.metadata import version

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def test_health_retorna_status_e_versao() -> None:
    client = TestClient(create_app(Settings()))

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": version("stemma")}
