import shutil
from pathlib import Path

from fastapi.testclient import TestClient

from app.config import Settings
from tests.conftest import add_export, ready_session_row
from tests.test_retention import make_backups


def test_uso_de_disco_por_categoria(client: TestClient, migrated: Settings) -> None:
    root = migrated.storage_root
    session_id = ready_session_row(client)
    add_export(client, root, session_id, age_min=1, size=300)
    add_export(client, root, session_id, age_min=2, size=200)
    stems = root / "sessions" / str(session_id) / "stems"
    stems.mkdir(parents=True)
    (stems / "vocals.mp3").write_bytes(b"x" * 1000)
    (stems / "vocals.peaks.json").write_bytes(b"x" * 24)
    make_backups(root, 3)  # 100 bytes cada
    (root / "backups" / "anotacoes.txt").write_bytes(b"x" * 999)  # fora do padrão

    body = client.get("/api/system/disk").json()

    assert body["stems_bytes"] == 1024
    assert body["exports_bytes"] == 500
    assert body["backups_bytes"] == 300
    assert (body["exports_keep"], body["backups_keep"]) == (5, 5)
    volume = shutil.disk_usage(Path(root))
    assert body["total_bytes"] == volume.total
    assert 0 < body["free_bytes"] <= body["total_bytes"]


def test_uso_de_disco_sem_nada_gravado(client: TestClient) -> None:
    body = client.get("/api/system/disk").json()

    assert (body["stems_bytes"], body["exports_bytes"], body["backups_bytes"]) == (0, 0, 0)
