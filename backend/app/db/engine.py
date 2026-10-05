import unicodedata
from typing import Any

from sqlalchemy import Engine, create_engine, event
from sqlalchemy.orm import Session, sessionmaker

BUSY_TIMEOUT_MS = 5000
# Collation do SQLite para ordenar texto em PT-BR: ignora caixa e acento ("Água" junto de "a").
TEXT_COLLATION = "pt_nocase"


def make_engine(database_url: str, *, foreign_keys: bool = True) -> Engine:
    """Engine do app. `foreign_keys=False` só para migrations: no SQLite, o batch do Alembic
    recria tabelas com DROP, o que dispararia `ON DELETE CASCADE` nas tabelas filhas."""
    is_sqlite = database_url.startswith("sqlite")
    engine = create_engine(
        database_url, connect_args={"check_same_thread": False} if is_sqlite else {}
    )
    if is_sqlite:

        def _on_connect(dbapi_connection: Any, _record: Any) -> None:
            _sqlite_setup(dbapi_connection, foreign_keys=foreign_keys)

        event.listen(engine, "connect", _on_connect)
    return engine


def _collation_key(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch)).casefold()


def _compare_text(a: str, b: str) -> int:
    ka, kb = _collation_key(a), _collation_key(b)
    return (ka > kb) - (ka < kb)


def _sqlite_setup(dbapi_connection: Any, *, foreign_keys: bool) -> None:
    dbapi_connection.create_collation(TEXT_COLLATION, _compare_text)
    cursor = dbapi_connection.cursor()
    try:
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute(f"PRAGMA busy_timeout={BUSY_TIMEOUT_MS}")
        cursor.execute(f"PRAGMA foreign_keys={'ON' if foreign_keys else 'OFF'}")
    finally:
        cursor.close()


def make_sessionmaker(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(engine, expire_on_commit=False)
