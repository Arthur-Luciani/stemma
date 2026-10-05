"""Posição na fila e ETA, calculados a partir da tabela `jobs` (ADR 0003).

A duração de cada etapa é estimada pela média móvel dos últimos jobs concluídos do mesmo
tipo, como razão "segundos de etapa por segundo de áudio" (download e separação crescem com
a duração da música). Sem a duração da música, vale a média em segundos absolutos; sem
histórico, os padrões abaixo.
"""

import math
import uuid
from collections import defaultdict
from collections.abc import Sequence
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import JobModel, SessionModel
from app.domain.enums import ACTIVE_JOB_STATES, PROCESS_STAGES, JobKind, JobState

# Quantos jobs concluídos entram na média móvel.
HISTORY_SIZE = 10
# Etapa única dos jobs sem etapas nomeadas (export).
RUN_STAGE = "run"

# Primeira estimativa, antes de haver histórico: (segundos por segundo de áudio, segundos).
_DEFAULTS: dict[str, tuple[float, float]] = {
    "downloading": (0.1, 30.0),
    "separating": (0.5, 120.0),
    RUN_STAGE: (0.05, 15.0),
}


def stages_for(kind: JobKind) -> tuple[str, ...]:
    if kind is JobKind.PROCESS:
        return tuple(stage.value for stage in PROCESS_STAGES)
    return (RUN_STAGE,)


@dataclass(frozen=True)
class JobEstimate:
    position: int | None
    eta_s: int | None


@dataclass
class StageStats:
    """Amostras de uma etapa: razões (s/s de áudio) e segundos absolutos."""

    ratios: list[float] = field(default_factory=list)
    seconds: list[float] = field(default_factory=list)

    def estimate(self, stage: str, duration_s: float | None) -> float:
        if duration_s and self.ratios:
            return _mean(self.ratios) * duration_s
        if self.seconds:
            return _mean(self.seconds)
        ratio, seconds = _DEFAULTS.get(stage, _DEFAULTS[RUN_STAGE])
        return ratio * duration_s if duration_s else seconds


@dataclass(frozen=True)
class ActiveJob:
    id: uuid.UUID
    kind: JobKind
    state: JobState
    stage: str | None
    progress: float
    duration_s: float | None


def collect_stats(
    history: Sequence[tuple[dict[str, float], float | None]],
) -> dict[str, StageStats]:
    """`history`: (durações por etapa, duração da música) dos jobs concluídos."""
    stats: dict[str, StageStats] = defaultdict(StageStats)
    for durations, duration_s in history:
        for stage, seconds in durations.items():
            stats[stage].seconds.append(seconds)
            if duration_s:
                stats[stage].ratios.append(seconds / duration_s)
    return stats


def remaining_seconds(job: ActiveJob, stats: dict[str, StageStats]) -> float:
    """Quanto falta para o job terminar, contando a etapa atual pelo progresso."""
    stages = stages_for(job.kind)
    if job.state is JobState.QUEUED:
        return sum(_stage(stats, s).estimate(s, job.duration_s) for s in stages)
    current = stages.index(job.stage) if job.stage in stages else 0
    left = 1 - min(max(job.progress, 0.0), 100.0) / 100
    total = _stage(stats, stages[current]).estimate(stages[current], job.duration_s) * left
    for stage in stages[current + 1 :]:
        total += _stage(stats, stage).estimate(stage, job.duration_s)
    return total


def estimate_queue(
    active: Sequence[ActiveJob], stats_by_kind: dict[JobKind, dict[str, StageStats]]
) -> dict[uuid.UUID, JobEstimate]:
    """`active` em ordem de execução (rodando primeiro, depois a fila por chegada).
    Cada kind tem seu worker, então posição e ETA acumulam por kind."""
    result: dict[uuid.UUID, JobEstimate] = {}
    elapsed: dict[JobKind, float] = defaultdict(float)
    position: dict[JobKind, int] = defaultdict(int)
    for job in active:
        elapsed[job.kind] += remaining_seconds(job, stats_by_kind.get(job.kind, {}))
        pos = None
        if job.state is JobState.QUEUED:
            position[job.kind] += 1
            pos = position[job.kind]
        result[job.id] = JobEstimate(position=pos, eta_s=math.ceil(elapsed[job.kind]))
    return result


class QueueEstimator:
    def __init__(self, db: Session) -> None:
        self.db = db

    def estimate(self) -> dict[uuid.UUID, JobEstimate]:
        rows = self.db.execute(
            select(
                JobModel.id,
                JobModel.kind,
                JobModel.state,
                JobModel.stage,
                JobModel.progress,
                SessionModel.duration_s,
            )
            .join(SessionModel, SessionModel.id == JobModel.session_id)
            .where(JobModel.state.in_(ACTIVE_JOB_STATES))
            .order_by(JobModel.created_at, JobModel.id)
        ).all()
        # Ordem de execução: quem está rodando, depois a fila por chegada (sort estável).
        active = sorted(
            (
                ActiveJob(
                    id=r.id,
                    kind=r.kind,
                    state=r.state,
                    stage=r.stage.value if r.stage else None,
                    progress=r.progress,
                    duration_s=r.duration_s,
                )
                for r in rows
            ),
            key=lambda j: j.state is not JobState.RUNNING,
        )
        kinds = {job.kind for job in active}
        return estimate_queue(active, {kind: self._stats(kind) for kind in kinds})

    def _stats(self, kind: JobKind) -> dict[str, StageStats]:
        rows = self.db.execute(
            select(JobModel.stage_durations, SessionModel.duration_s)
            .join(SessionModel, SessionModel.id == JobModel.session_id)
            .where(
                JobModel.kind == kind,
                JobModel.state == JobState.DONE,
                JobModel.stage_durations.is_not(None),
            )
            .order_by(JobModel.finished_at.desc())
            .limit(HISTORY_SIZE)
        ).all()
        return collect_stats([(r.stage_durations, r.duration_s) for r in rows])


def _stage(stats: dict[str, StageStats], stage: str) -> StageStats:
    return stats.get(stage) or StageStats()


def _mean(values: list[float]) -> float:
    return sum(values) / len(values)
