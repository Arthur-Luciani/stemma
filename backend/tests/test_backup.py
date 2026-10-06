import sqlite3
from collections.abc import Iterator
from pathlib import Path

import pytest

from app.cli import main
from app.config import Settings, get_settings
from app.services.backup import backup_database, restore_database, sqlite_path


def tables(db: Path) -> set[str]:
    with sqlite3.connect(db) as conn:
        rows = conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'").fetchall()
    conn.close()
    return {name for (name,) in rows}


def revision(db: Path) -> str:
    with sqlite3.connect(db) as conn:
        (rev,) = conn.execute("SELECT version_num FROM alembic_version").fetchone()
    conn.close()
    return str(rev)


@pytest.fixture
def cli_env(monkeypatch: pytest.MonkeyPatch, migrated: Settings) -> Iterator[None]:
    monkeypatch.setenv("STORAGE_ROOT", str(migrated.storage_root))
    monkeypatch.setenv("DATABASE_URL", migrated.database_url)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_backup_copia_tabelas_e_revisao(migrated: Settings, tmp_path: Path) -> None:
    dest = tmp_path / "backups" / "stemma.db"

    backup_database(migrated.database_url, dest)

    src = sqlite_path(migrated.database_url)
    assert {"sessions", "jobs", "alembic_version"} <= tables(dest)
    assert revision(dest) == revision(src)


def test_backup_nao_sobrescreve(migrated: Settings, tmp_path: Path) -> None:
    dest = tmp_path / "stemma.db"
    dest.write_bytes(b"x")

    with pytest.raises(Exception, match="já existe"):
        backup_database(migrated.database_url, dest)


def test_restore_volta_o_banco(migrated: Settings, tmp_path: Path) -> None:
    dest = tmp_path / "antes.db"
    backup_database(migrated.database_url, dest)
    db = sqlite_path(migrated.database_url)
    with sqlite3.connect(db) as conn:
        conn.execute("CREATE TABLE lixo (x)")
    conn.close()

    restore_database(migrated.database_url, dest)

    assert "lixo" not in tables(db)


def test_banco_que_nao_e_sqlite_falha() -> None:
    with pytest.raises(Exception, match="SQLite"):
        sqlite_path("postgresql://localhost/stemma")


def test_cli_backup_e_restore(cli_env: None, tmp_path: Path) -> None:
    dest = tmp_path / "cli.db"

    assert main(["backup", "--dest", str(dest)]) == 0
    assert dest.is_file()
    assert main(["restore", "--src", str(dest)]) == 0
    assert main(["restore", "--src", str(tmp_path / "nao-existe.db")]) == 1
