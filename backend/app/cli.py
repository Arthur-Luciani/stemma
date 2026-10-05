"""Comandos de manutenção: `uv run python -m app.cli cleanup [--dry-run]`."""

import argparse
import logging
import sys

from app.config import get_settings
from app.db.engine import make_engine, make_sessionmaker
from app.logging_setup import configure_logging
from app.services.cleanup import CleanupService
from app.storage import Storage

logger = logging.getLogger("app.cli")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m app.cli", description="Manutenção do Stemma")
    commands = parser.add_subparsers(dest="command", required=True)
    cleanup = commands.add_parser("cleanup", help="remove arquivos órfãos do STORAGE_ROOT")
    cleanup.add_argument("--dry-run", action="store_true", help="só lista o que seria removido")
    args = parser.parse_args(argv)

    settings = get_settings()
    configure_logging(settings.log_level)
    engine = make_engine(settings.database_url)
    try:
        with make_sessionmaker(engine)() as db:
            report = CleanupService(db, Storage(settings.storage_root)).run(dry_run=args.dry_run)
    finally:
        engine.dispose()

    verb = "Seriam removidos" if args.dry_run else "Removidos"
    logger.info(
        "%s %d itens (%.1f MB) de %s",
        verb,
        len(report.removed),
        report.freed_bytes / 1_000_000,
        settings.storage_root,
    )
    for rel in report.removed:
        logger.info("  %s", rel)
    return 0


if __name__ == "__main__":
    sys.exit(main())
