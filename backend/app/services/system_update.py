"""Atualização do Stemma pelo app (ADR 0015).

O backend só verifica se há versão nova e dispara a tarefa agendada, que roda o instalador
fora do serviço. O estado fica no banco: `running` gravado aqui; o resultado, pelo CLI
(`python -m app.cli update-result`), que a tarefa roda no fim.
"""

import logging
from collections.abc import Callable
from datetime import datetime

from sqlalchemy.orm import Session

from app import __version__
from app.db.models import SystemUpdateModel
from app.db.types import utcnow
from app.domain.enums import UpdateState
from app.domain.errors import AppError, ConflictError
from app.domain.releases import format_version, parse_release_notes, parse_version
from app.pipeline.updater import GitHubReleases, Release, UpdateTask, UpdateTaskError
from app.schemas.system import (
    ReleaseNotes,
    ReleaseNotesSection,
    SystemUpdateOut,
    UpdateRunOut,
)
from app.services.jobs import JobService
from app.services.update_guard import RUNNING_TIMEOUT, is_running, latest_update

logger = logging.getLogger(__name__)

STALE_MESSAGE = (
    "A atualização não terminou (o PC pode ter desligado no meio). "
    "Veja os logs na pasta logs da instalação."
)


class SystemUpdateService:
    def __init__(
        self,
        db: Session,
        releases: GitHubReleases,
        task: UpdateTask,
        jobs: JobService,
        *,
        current_version: str = __version__,
        clock: Callable[[], datetime] = utcnow,
    ) -> None:
        self.db = db
        self.releases = releases
        self.task = task
        self.jobs = jobs
        self.current_version = current_version
        self.clock = clock

    def status(self) -> SystemUpdateOut:
        run = self._last_run()
        listing = self.releases.list()
        current = parse_version(self.current_version)
        latest = _latest_installable(listing.releases) if listing else None
        available = bool(latest and current and latest.version > current)
        notes: list[ReleaseNotes] = []
        if latest and current and listing:
            newer = [r for r in listing.releases if current < r.version <= latest.version]
            for release in sorted(newer, key=lambda r: r.version, reverse=True):
                sections = [
                    ReleaseNotesSection(title=s.title, items=s.items)
                    for s in parse_release_notes(release.body)
                ]
                version = format_version(release.version)
                notes.append(ReleaseNotes(version=version, sections=sections))
        return SystemUpdateOut(
            current_version=self.current_version,
            check="ok" if listing else "unavailable",
            checked_at=listing.checked_at if listing else None,
            latest_version=format_version(latest.version) if latest else None,
            available=available,
            notes=notes,
            can_update=self.task.configured,
            active_jobs=self.jobs.count_active(),
            last_run=_run_out(run) if run else None,
        )

    def start(self) -> UpdateRunOut:
        """Grava `running` e dispara a tarefa. Responde na hora; quem atualiza é a tarefa."""
        run = self._last_run()
        if run is not None and run.state == UpdateState.RUNNING:
            raise ConflictError("update_running", "Já há uma atualização em andamento.")
        if not self.task.configured:
            raise ConflictError(
                "update_not_supported",
                "Esta instalação não atualiza pelo app. Rode no PC o instalador da versão nova.",
            )
        if self.jobs.count_active() > 0:
            raise ConflictError(
                "jobs_active",
                "Espere terminar o processamento e os exports em andamento para atualizar.",
            )
        listing = self.releases.list()
        if listing is None:
            raise AppError(
                "update_check_failed",
                "Não foi possível verificar se há versão nova. Tente de novo em alguns minutos.",
                503,
            )
        current = parse_version(self.current_version)
        latest = _latest_installable(listing.releases)
        if latest is None or current is None or latest.version <= current:
            raise ConflictError("update_unavailable", "O Stemma já está na versão mais recente.")

        target = format_version(latest.version)
        row = SystemUpdateModel(
            from_version=self.current_version,
            target_version=target,
            state=UpdateState.RUNNING,
            created_at=self.clock(),
        )
        self.db.add(row)
        self.db.commit()
        logger.info("Atualização %s → %s pedida pelo app", self.current_version, target)
        try:
            self.task.run()
        except UpdateTaskError as exc:
            row.state = UpdateState.FAILED
            row.message = f"Não foi possível iniciar a atualização: {exc}"
            row.finished_at = self.clock()
            self.db.commit()
            raise AppError("update_start_failed", row.message, 502) from exc
        return _run_out(row)

    def _last_run(self) -> SystemUpdateModel | None:
        run = latest_update(self.db)
        if (
            run is not None
            and run.state == UpdateState.RUNNING
            and not is_running(run, self.clock())
        ):
            logger.warning("Atualização %s sem resultado há mais de %s", run.id, RUNNING_TIMEOUT)
            run.state = UpdateState.FAILED
            run.message = STALE_MESSAGE
            run.finished_at = self.clock()
            self.db.commit()
        return run


def record_update_result(
    db: Session,
    state: UpdateState,
    message: str | None,
    *,
    clock: Callable[[], datetime] = utcnow,
) -> bool:
    """Grava o resultado na última atualização pedida, se ela ainda estiver `running` (usado
    pelo CLI, no fim da tarefa). False se não houver (tarefa rodada à mão): nada muda."""
    if state == UpdateState.RUNNING:
        raise ValueError("o resultado precisa ser succeeded ou failed")
    run = latest_update(db)
    if run is None or run.state != UpdateState.RUNNING:
        logger.warning("Resultado de atualização sem pedido em andamento: %s", state)
        return False
    run.state = state
    run.message = message or None
    run.finished_at = clock()
    db.commit()
    logger.info("Atualização %s → %s: %s", run.from_version, run.target_version, state)
    return True


def _latest_installable(releases: list[Release]) -> Release | None:
    candidates = [r for r in releases if r.has_installer]
    return max(candidates, key=lambda r: r.version) if candidates else None


def _run_out(row: SystemUpdateModel) -> UpdateRunOut:
    return UpdateRunOut(
        id=row.id,
        from_version=row.from_version,
        target_version=row.target_version,
        state=row.state,
        message=row.message,
        created_at=row.created_at,
        finished_at=row.finished_at,
    )
