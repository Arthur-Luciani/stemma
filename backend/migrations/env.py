"""Ambiente do Alembic. URL do banco: `config.attributes["database_url"]` (testes) ou Settings."""

from logging.config import fileConfig
from pathlib import Path
from typing import Any

from alembic import context
from alembic.autogenerate.api import AutogenContext

from app.config import get_settings
from app.db.engine import make_engine
from app.db.models import Base
from app.db.types import UTCDateTime

config = context.config

if config.config_file_name is not None and not config.attributes.get("skip_logging_config"):
    fileConfig(config.config_file_name, disable_existing_loggers=False)

target_metadata = Base.metadata


def _database_url() -> str:
    url = config.attributes.get("database_url")
    return str(url) if url else get_settings().database_url


def _render_item(type_: str, obj: Any, autogen_context: AutogenContext) -> str | bool:
    # Migrations não importam `app`: o UTCDateTime vira DateTime puro (mesmo tipo no banco).
    if type_ == "type" and isinstance(obj, UTCDateTime):
        return "sa.DateTime()"
    return False


def run_migrations_offline() -> None:
    context.configure(
        url=_database_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        render_as_batch=True,
        render_item=_render_item,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    url = _database_url()
    if url.startswith("sqlite:///"):
        # Garante que a pasta do arquivo exista (ex.: STORAGE_ROOT novo).
        Path(url.removeprefix("sqlite:///")).parent.mkdir(parents=True, exist_ok=True)
    engine = make_engine(url)
    try:
        with engine.connect() as connection:
            context.configure(
                connection=connection,
                target_metadata=target_metadata,
                render_as_batch=True,
                compare_type=True,
                render_item=_render_item,
            )
            with context.begin_transaction():
                context.run_migrations()
    finally:
        engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
