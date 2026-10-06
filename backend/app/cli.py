"""Comandos de manutenção:

- `uv run python -m app.cli cleanup [--dry-run]`
- `uv run python -m app.cli backup --dest <arquivo>` / `restore --src <arquivo>` (usados pelo
  `deploy/update.ps1`)
- `uv run python -m app.cli update-result --state succeeded|failed [--message <texto>]` (usado
  pela tarefa agendada no fim da atualização pelo app, ADR 0015)
- `uv run python -m app.cli update-target`: imprime a versão escolhida pelo app (`1.5.1`) da
  atualização em andamento; sai com 1 se não houver (a tarefa instala exatamente essa)
"""

import argparse
import logging
import sys
from pathlib import Path

from app.config import get_settings
from app.db.engine import make_engine, make_sessionmaker
from app.db.types import utcnow
from app.domain.enums import UpdateState
from app.domain.errors import AppError
from app.logging_setup import configure_logging
from app.services.backup import backup_database, restore_database
from app.services.cleanup import CleanupService
from app.services.system_update import record_update_result
from app.services.update_guard import is_running, latest_update
from app.storage import Storage

logger = logging.getLogger("app.cli")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m app.cli", description="Manutenção do Stemma")
    commands = parser.add_subparsers(dest="command", required=True)
    cleanup = commands.add_parser("cleanup", help="remove arquivos órfãos do STORAGE_ROOT")
    cleanup.add_argument("--dry-run", action="store_true", help="só lista o que seria removido")
    cleanup.add_argument(
        "--min-age-minutes",
        type=float,
        default=60,
        help="só remove o que está parado há pelo menos isso (padrão 60; seguro com o app no ar)",
    )
    backup = commands.add_parser("backup", help="copia o banco SQLite (API de backup)")
    backup.add_argument("--dest", type=Path, required=True, help="arquivo de destino (novo)")
    restore = commands.add_parser("restore", help="sobrescreve o banco com um backup (app parado)")
    restore.add_argument("--src", type=Path, required=True, help="arquivo de backup")
    commands.add_parser("update-target", help="versão da atualização em andamento")
    result = commands.add_parser(
        "update-result", help="grava o resultado da atualização pedida pelo app"
    )
    result.add_argument(
        "--state", required=True, choices=[UpdateState.SUCCEEDED, UpdateState.FAILED]
    )
    result.add_argument("--message", default=None, help="motivo da falha (PT-BR)")
    args = parser.parse_args(argv)

    settings = get_settings()
    configure_logging(settings.log_level)
    try:
        if args.command == "backup":
            backup_database(settings.database_url, args.dest)
            return 0
        if args.command == "restore":
            restore_database(settings.database_url, args.src)
            return 0
        if args.command == "update-target":
            return _update_target(settings.database_url)
        if args.command == "update-result":
            return _update_result(settings.database_url, UpdateState(args.state), args.message)
    except AppError as exc:
        logger.error("%s", exc.message)
        return 1
    return _cleanup(settings.database_url, settings.storage_root, args)


def _update_target(database_url: str) -> int:
    engine = make_engine(database_url)
    try:
        with make_sessionmaker(engine)() as db:
            run = latest_update(db)
            if not is_running(run, utcnow()):
                logger.error("Nenhuma atualização em andamento")
                return 1
            assert run is not None
            # stdout: lido pelo motor (Invoke-StemmaAppUpdate); o log vai para o stderr.
            sys.stdout.write(f"{run.target_version}\n")
    finally:
        engine.dispose()
    return 0


def _update_result(database_url: str, state: UpdateState, message: str | None) -> int:
    engine = make_engine(database_url)
    try:
        with make_sessionmaker(engine)() as db:
            record_update_result(db, state, message)
    finally:
        engine.dispose()
    return 0


def _cleanup(database_url: str, storage_root: Path, args: argparse.Namespace) -> int:
    engine = make_engine(database_url)
    try:
        with make_sessionmaker(engine)() as db:
            report = CleanupService(db, Storage(storage_root)).run(
                dry_run=args.dry_run, min_age_s=args.min_age_minutes * 60
            )
    finally:
        engine.dispose()

    verb = "Seriam removidos" if args.dry_run else "Removidos"
    logger.info(
        "%s %d itens (%.1f MB) de %s",
        verb,
        len(report.removed),
        report.freed_bytes / 1_000_000,
        storage_root,
    )
    for rel in report.removed:
        logger.info("  %s", rel)
    return 0


if __name__ == "__main__":
    sys.exit(main())
