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


def test_0005_converte_presets_dos_exports_e_semeia_a_tabela(settings: Settings) -> None:
    from alembic import command

    from tests.conftest import alembic_config

    config = alembic_config(settings.database_url)
    command.upgrade(config, "0004")
    engine = make_engine(settings.database_url)
    try:
        with engine.begin() as conn:
            conn.execute(
                text(
                    "INSERT INTO sessions (id, code, source_url, artist, title, artist_key,"
                    " search_key, state, progress, created_at, updated_at) VALUES"
                    " ('a1', 'ST-001', 'u', 'a', 't', 'a', 'a', 'ready', 0, '2026-01-01',"
                    " '2026-01-01')"
                )
            )
            stems = '{"vocals": {"volume": 100, "pan": 0, "mute": false, "solo": false}}'
            for i, preset in enumerate(("no_vocals", "custom", None)):
                conn.execute(
                    text(
                        "INSERT INTO exports (id, session_id, format, preset, levels, state,"
                        " progress, created_at, updated_at) VALUES (:id, 'a1', 'wav', :preset,"
                        " :levels, 'done', 100, '2026-01-01', '2026-01-01')"
                    ),
                    {"id": f"e{i}", "preset": preset, "levels": stems},
                )
            conn.execute(
                text(
                    "INSERT INTO mix_states (session_id, stems, preset, updated_at)"
                    " VALUES ('a1', :levels, 'no_vocals', '2026-01-01')"
                ),
                {"levels": stems},
            )
    finally:
        engine.dispose()

    command.upgrade(config, "0005")

    engine = make_engine(settings.database_url)
    try:
        with engine.connect() as conn:
            exports = conn.execute(text("SELECT id, preset FROM exports ORDER BY id")).all()
            presets = (
                conn.execute(text("SELECT name FROM mix_presets ORDER BY position")).scalars().all()
            )
            mix_columns = [r[1] for r in conn.execute(text("PRAGMA table_info(mix_states)"))]
            mixes = conn.execute(text("SELECT count(*) FROM mix_states")).scalar_one()
    finally:
        engine.dispose()

    assert [tuple(r) for r in exports] == [("e0", "Sem voz"), ("e1", "Personalizado"), ("e2", None)]
    assert list(presets) == ["Original", "Sem voz", "Sem bateria", "Sem baixo", "Só voz"]
    assert "preset" not in mix_columns
    assert mixes == 1


def test_0005_downgrade_volta_o_enum(settings: Settings) -> None:
    from alembic import command

    from tests.conftest import alembic_config

    config = alembic_config(settings.database_url)
    command.upgrade(config, "head")
    command.downgrade(config, "0004")
    command.upgrade(config, "head")


def test_0006_marca_so_os_de_fabrica_com_o_nome_original(settings: Settings) -> None:
    from alembic import command

    from tests.conftest import alembic_config

    config = alembic_config(settings.database_url)
    command.upgrade(config, "0005")
    engine = make_engine(settings.database_url)
    try:
        with engine.begin() as conn:
            conn.execute(text("UPDATE mix_presets SET name = 'Karaokê' WHERE name = 'Sem voz'"))
        command.upgrade(config, "head")
        with engine.connect() as conn:
            rows = conn.execute(
                text("SELECT name, icon, color FROM mix_presets ORDER BY position")
            ).all()
    finally:
        engine.dispose()

    assert [tuple(r) for r in rows] == [
        ("Original", "graphic_eq", None),
        ("Karaokê", None, None),
        ("Sem bateria", "volume_off", "drums"),
        ("Sem baixo", "volume_off", "bass"),
        ("Só voz", "mic", "vocals"),
    ]
    command.downgrade(config, "0005")
    command.upgrade(config, "head")
