from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import text

from app.config import Settings
from app.db.engine import make_engine
from app.db.models import Base


def test_migrations_batem_com_os_models(migrated: Settings) -> None:
    engine = make_engine(migrated.database_url)
    try:
        with engine.connect() as conn:
            context = MigrationContext.configure(conn, opts={"compare_type": True})
            diff = compare_metadata(context, Base.metadata)
    finally:
        engine.dispose()

    assert diff == [], f"Models divergem das migrations; gere uma nova migration: {diff}"


def test_pragmas_do_sqlite(migrated: Settings) -> None:
    engine = make_engine(migrated.database_url)
    try:
        with engine.connect() as conn:
            assert conn.execute(text("PRAGMA journal_mode")).scalar() == "wal"
            assert conn.execute(text("PRAGMA foreign_keys")).scalar() == 1
            assert conn.execute(text("PRAGMA busy_timeout")).scalar() == 5000
    finally:
        engine.dispose()


def test_baseline_semeia_contador_de_codigo(migrated: Settings) -> None:
    engine = make_engine(migrated.database_url)
    try:
        with engine.connect() as conn:
            value = conn.execute(
                text("SELECT value FROM counters WHERE name = 'session_code'")
            ).scalar()
    finally:
        engine.dispose()

    assert value == 0
