from pathlib import Path

import pytest

from app.config import REPO_DIR, Settings


def test_storage_root_relativo_resolve_a_partir_do_repo(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.chdir(Path(__file__).parent)
    monkeypatch.setenv("STORAGE_ROOT", "dados")

    assert Settings(_env_file=None).storage_root == (REPO_DIR / "dados").resolve()


def test_storage_root_absoluto_e_mantido(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("STORAGE_ROOT", str(tmp_path))

    assert Settings(_env_file=None).storage_root == tmp_path
