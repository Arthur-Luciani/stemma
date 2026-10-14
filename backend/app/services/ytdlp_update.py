"""Atualização só do yt-dlp (ADR 0016).

Como a do Stemma (ADR 0015), quem atualiza é uma tarefa agendada (`\\Stemma\\AtualizarYtDlp`),
fora do serviço, que ela para e sobe de novo. A tarefa roda todo dia e também quando o app
pede. O estado fica no banco (`system_updates`, componente `ytdlp`): `running` gravado aqui
(pedido do app) ou pelo CLI `ytdlp-begin` (tarefa diária); o resultado, pelo CLI
`ytdlp-result`.
"""

import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy.orm import Session
from yt_dlp.version import __version__ as ytdlp_version

from app.db.models import SystemUpdateModel
from app.db.types import utcnow
from app.domain.enums import UpdateComponent, UpdateState
from app.domain.errors import AppError, ConflictError
from app.domain.releases import parse_ytdlp_version
from app.pipeline.updater import UpdateTask, UpdateTaskError, YtDlpLatest, YtDlpReleases
from app.schemas.system import UpdateRunOut, YtDlpStatusOut
from app.services.jobs import count_active_jobs
from app.services.system_update import run_out
from app.services.update_guard import is_running, last_run, record_result, running_update

logger = logging.getLogger(__name__)

# A tarefa roda todo dia: uma versão nova que segue sem instalar depois disso é a tarefa
# falhando (ou desligada), e aí o app avisa.
STALE_AFTER = timedelta(days=2)


@dataclass(frozen=True)
class TaskStart:
    """O que a tarefa agendada deve fazer (`ytdlp-begin`): instalar `target` ou pular."""

    target: str | None
    from_version: str | None = None
    skip_reason: str | None = None


class YtDlpUpdateService:
    def __init__(
        self,
        db: Session,
        releases: YtDlpReleases,
        task: UpdateTask,
        *,
        installed_version: str = ytdlp_version,
        clock: Callable[[], datetime] = utcnow,
    ) -> None:
        self.db = db
        self.releases = releases
        self.task = task
        self.installed_version = installed_version
        self.clock = clock

    def status(self) -> YtDlpStatusOut:
        run = self._last_run()
        latest = self.releases.latest()
        available = self._is_newer(latest)
        published = latest.published_at if latest else None
        return YtDlpStatusOut(
            installed_version=self.installed_version,
            check="ok" if latest else "unavailable",
            checked_at=latest.checked_at if latest else None,
            latest_version=latest.version if latest else None,
            latest_published_at=published,
            available=available,
            stale=bool(available and published and self.clock() - published > STALE_AFTER),
            can_update=self.task.configured,
            active_jobs=count_active_jobs(self.db),
            last_run=run_out(run) if run else None,
        )

    def start(self) -> UpdateRunOut:
        """Pedido do app: grava `running` e dispara a tarefa, que instala exatamente essa
        versão. Responde na hora."""
        self._last_run()  # expira um `running` que não terminou
        if running_update(self.db, self.clock()) is not None:
            raise ConflictError("update_running", "Já há uma atualização em andamento.")
        if not self.task.configured:
            raise ConflictError(
                "update_not_supported",
                "Esta instalação não atualiza o yt-dlp pelo app. Rode no PC o instalador da "
                "última versão do Stemma.",
            )
        if count_active_jobs(self.db) > 0:
            raise ConflictError(
                "jobs_active",
                "Espere terminar o processamento e os exports em andamento para atualizar.",
            )
        latest = self.releases.latest()
        if latest is None:
            raise AppError(
                "update_check_failed",
                "Não foi possível verificar se há yt-dlp novo. Tente de novo em alguns minutos.",
                503,
            )
        if not self._is_newer(latest):
            raise ConflictError("update_unavailable", "O yt-dlp já está na versão mais recente.")

        row = self._create_run(latest.version, "pedida pelo app")
        try:
            self.task.run()
        except UpdateTaskError as exc:
            row.state = UpdateState.FAILED
            row.message = f"Não foi possível iniciar a atualização do yt-dlp: {exc}"
            row.finished_at = self.clock()
            self.db.commit()
            raise AppError("update_start_failed", row.message, 502) from exc
        return run_out(row)

    def begin_task(self) -> TaskStart:
        """Início da tarefa agendada (CLI `ytdlp-begin`). Com um pedido do app em andamento,
        devolve a versão dele. Sem pedido (gatilho diário, `update.ps1 -YtDlpOnly`), decide
        aqui: só segue sem outra atualização, sem job ativo e com versão nova, e então grava
        `running`, que trava jobs novos até o resultado."""
        run = self._last_run()
        now = self.clock()
        if run is not None and is_running(run, now):
            return TaskStart(target=run.target_version, from_version=run.from_version)
        if running_update(self.db, now) is not None:
            return TaskStart(target=None, skip_reason="há uma atualização do Stemma em andamento")
        active = count_active_jobs(self.db)
        if active > 0:
            return TaskStart(target=None, skip_reason=f"há {active} job(s) na fila ou rodando")
        latest = self.releases.latest()
        if latest is None:
            return TaskStart(target=None, skip_reason="não foi possível consultar o PyPI")
        if not self._is_newer(latest):
            return TaskStart(
                target=None, skip_reason=f"o yt-dlp {self.installed_version} já é o mais recente"
            )
        row = self._create_run(latest.version, "automática")
        return TaskStart(target=row.target_version, from_version=row.from_version)

    def _create_run(self, target: str, origin: str) -> SystemUpdateModel:
        row = SystemUpdateModel(
            component=UpdateComponent.YTDLP,
            from_version=self.installed_version,
            target_version=target,
            state=UpdateState.RUNNING,
            created_at=self.clock(),
        )
        self.db.add(row)
        self.db.commit()
        logger.info("Atualização do yt-dlp %s → %s %s", self.installed_version, target, origin)
        return row

    def _is_newer(self, latest: YtDlpLatest | None) -> bool:
        installed = parse_ytdlp_version(self.installed_version)
        newest = parse_ytdlp_version(latest.version) if latest else None
        return bool(installed and newest and newest > installed)

    def _last_run(self) -> SystemUpdateModel | None:
        return last_run(self.db, UpdateComponent.YTDLP, self.clock())


def record_ytdlp_result(
    db: Session,
    state: UpdateState,
    message: str | None,
    *,
    clock: Callable[[], datetime] = utcnow,
) -> bool:
    """Resultado da atualização do yt-dlp (CLI `ytdlp-result`, no fim da tarefa)."""
    return record_result(db, UpdateComponent.YTDLP, state, message, clock())
