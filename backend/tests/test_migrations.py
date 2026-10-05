from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import String, text

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


def _rebuild_sessions_table(database_url: str, *, foreign_keys: bool) -> int:
    """Recria `sessions` como uma migration em batch faria; devolve quantos eventos sobraram."""
    engine = make_engine(database_url, foreign_keys=foreign_keys)
    try:
        with engine.begin() as conn:
            conn.execute(
                text(
                    "INSERT INTO sessions (id, code, source_url, artist, title, artist_key,"
                    " search_key, state, progress, created_at, updated_at) VALUES"
                    " ('a1', 'ST-001', 'u', 'a', 't', 'a', 'a', 'draft', 0, '2026-01-01',"
                    " '2026-01-01')"
                )
            )
            conn.execute(
                text(
                    "INSERT INTO session_events (session_id, type, payload, created_at)"
                    " VALUES ('a1', 'created', '{}', '2026-01-01')"
                )
            )
        with engine.begin() as conn:
            ops = Operations(MigrationContext.configure(conn))
            with ops.batch_alter_table("sessions", recreate="always") as batch:
                batch.alter_column("title", existing_type=String(200), type_=String(300))
        with engine.connect() as conn:
            return int(conn.execute(text("SELECT count(*) FROM session_events")).scalar_one())
    finally:
        engine.dispose()


def test_batch_com_fks_desligadas_preserva_filhos(migrated: Settings) -> None:
    # Como o env.py roda as migrations.
    assert _rebuild_sessions_table(migrated.database_url, foreign_keys=False) == 1


def test_batch_com_fks_ligadas_apagaria_filhos(migrated: Settings) -> None:
    # Controle: prova que o teste acima detecta o problema.
    assert _rebuild_sessions_table(migrated.database_url, foreign_keys=True) == 0
