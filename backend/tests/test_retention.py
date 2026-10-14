import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.domain.enums import ExportState
from app.services.retention import prune_backups, select_backups_to_prune
from app.storage import BACKUPS_DIR, Storage
from tests.conftest import add_export, export_ids, ready_session_row


def make_backups(root: Path, count: int) -> list[Path]:
    """`count` backups; o de índice maior é o mais novo."""
    folder = root / BACKUPS_DIR
    folder.mkdir(parents=True, exist_ok=True)
    files = []
    for index in range(count):
        file = folder / f"stemma-v1.{index}.0-to-v1.{index + 1}.0-20261001-1200{index:02d}.db"
        file.write_bytes(b"x" * 100)
        os.utime(file, (1_700_000_000 + index * 60, 1_700_000_000 + index * 60))
        files.append(file)
    return files


# --- backups ----------------------------------------------------------------


def test_backups_ficam_so_os_mais_novos(tmp_path: Path) -> None:
    files = make_backups(tmp_path, 8)

    doomed = select_backups_to_prune(files, keep=5)

    assert doomed == [files[2], files[1], files[0]]


def test_com_keep_1_o_backup_mais_novo_nunca_sai(tmp_path: Path) -> None:
    files = make_backups(tmp_path, 4)

    doomed = select_backups_to_prune(files, keep=1)

    assert files[-1] not in doomed
    assert len(doomed) == 3


def test_backups_ignora_o_que_nao_segue_o_padrao(tmp_path: Path) -> None:
    files = make_backups(tmp_path, 3)
    other = files[0].parent / "anotacoes.txt"
    other.write_text("meu")
    os.utime(other, (1, 1))

    doomed = select_backups_to_prune([*files, other], keep=1)

    assert other not in doomed
    assert doomed == [files[1], files[0]]


def test_prune_backups_apaga_e_conta_os_bytes(tmp_path: Path) -> None:
    files = make_backups(tmp_path, 7)

    report = prune_backups(Storage(tmp_path), keep=5)

    assert [f.exists() for f in files] == [False, False, True, True, True, True, True]
    assert report.freed_bytes == 200
    assert len(report.removed) == 2
    assert report.removed[0].startswith("backups/stemma-")


def test_prune_backups_dry_run_nao_apaga(tmp_path: Path) -> None:
    files = make_backups(tmp_path, 7)

    report = prune_backups(Storage(tmp_path), keep=5, dry_run=True)

    assert all(f.exists() for f in files)
    assert len(report.removed) == 2


def test_prune_backups_sem_pasta(tmp_path: Path) -> None:
    assert prune_backups(Storage(tmp_path), keep=5).removed == []


# --- exports (pedir um novo export abre espaço) -----------------------------


def test_novo_export_apaga_os_mais_antigos(client: TestClient, migrated: Settings) -> None:
    root = migrated.storage_root
    session_id = ready_session_row(client)
    old = [
        add_export(client, root, session_id, age_min=60 - i) for i in range(5)
    ]  # o 1º é o + velho

    response = client.post(f"/api/sessions/{session_id}/exports", json={"format": "mp3"})

    assert response.status_code == 201
    ids = export_ids(client, session_id)
    assert len(ids) == 5  # 4 antigos + o novo
    assert old[0].id not in ids
    assert not (root / str(old[0].path)).exists()
    assert (root / str(old[1].path)).exists()
    listed = client.get(f"/api/sessions/{session_id}/exports").json()["items"]
    assert str(old[0].id) not in [e["id"] for e in listed]


def test_export_na_fila_ou_rodando_nunca_e_apagado(client: TestClient, migrated: Settings) -> None:
    client.app.state.settings.exports_keep = 1  # type: ignore[attr-defined]
    root = migrated.storage_root
    session_id = ready_session_row(client)
    running = add_export(client, root, session_id, age_min=500, state=ExportState.RUNNING)
    done = [add_export(client, root, session_id, age_min=10 - i) for i in range(3)]

    client.post(f"/api/sessions/{session_id}/exports", json={"format": "mp3"})

    ids = export_ids(client, session_id)
    assert running.id in ids
    assert not any(d.id in ids for d in done)


def test_arquivo_que_nao_da_para_apagar_mantem_a_linha(
    client: TestClient, migrated: Settings, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = migrated.storage_root
    session_id = ready_session_row(client)
    old = [add_export(client, root, session_id, age_min=60 - i) for i in range(5)]
    locked = root / str(old[0].path)
    real_unlink = Path.unlink

    def unlink(self: Path, missing_ok: bool = False) -> None:
        if self == locked:
            raise PermissionError("em uso")
        real_unlink(self, missing_ok=missing_ok)

    monkeypatch.setattr(Path, "unlink", unlink)

    response = client.post(f"/api/sessions/{session_id}/exports", json={"format": "mp3"})

    assert response.status_code == 201
    assert old[0].id in export_ids(client, session_id)
    assert locked.exists()


def test_download_de_export_podado_nao_da_500(client: TestClient, migrated: Settings) -> None:
    root = migrated.storage_root
    session_id = ready_session_row(client)
    old = [add_export(client, root, session_id, age_min=60 - i) for i in range(5)]
    client.post(f"/api/sessions/{session_id}/exports", json={"format": "mp3"})

    response = client.get(f"/api/exports/{old[0].id}/file")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "export_not_found"
