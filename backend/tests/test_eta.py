import uuid

import pytest

from app.domain.enums import JobKind, JobState
from app.pipeline.eta import ActiveJob, StageStats, collect_stats, estimate_queue, remaining_seconds


def _job(
    state: JobState,
    *,
    kind: JobKind = JobKind.PROCESS,
    stage: str | None = None,
    progress: float = 0.0,
    duration_s: float | None = 100.0,
) -> ActiveJob:
    return ActiveJob(
        id=uuid.uuid4(),
        kind=kind,
        state=state,
        stage=stage,
        progress=progress,
        duration_s=duration_s,
    )


def test_sem_historico_usa_padroes_proporcionais_a_duracao() -> None:
    # Padrões: download 0,1 s/s e separação 0,5 s/s de áudio.
    assert remaining_seconds(_job(JobState.QUEUED), {}) == pytest.approx(60.0)


def test_sem_duracao_nem_historico_usa_segundos_absolutos() -> None:
    assert remaining_seconds(_job(JobState.QUEUED, duration_s=None), {}) == pytest.approx(150.0)


def test_media_movel_pela_razao_com_a_duracao() -> None:
    stats = collect_stats(
        [
            ({"downloading": 10.0, "separating": 50.0}, 100.0),
            ({"downloading": 30.0, "separating": 150.0}, 300.0),
        ]
    )

    assert stats["downloading"].ratios == [0.1, 0.1]
    # Música de 200 s: 0,1·200 + 0,5·200.
    assert remaining_seconds(_job(JobState.QUEUED, duration_s=200.0), stats) == pytest.approx(120.0)


def test_historico_sem_duracao_usa_media_absoluta() -> None:
    stats = collect_stats([({"downloading": 10.0}, None), ({"downloading": 20.0}, None)])

    assert stats["downloading"].estimate("downloading", 100.0) == pytest.approx(15.0)


def test_job_rodando_conta_o_que_falta_da_etapa_atual() -> None:
    stats = {"downloading": StageStats(ratios=[0.1]), "separating": StageStats(ratios=[0.5])}

    downloading = _job(JobState.RUNNING, stage="downloading", progress=50)
    separating = _job(JobState.RUNNING, stage="separating", progress=80)

    assert remaining_seconds(downloading, stats) == pytest.approx(5.0 + 50.0)
    assert remaining_seconds(separating, stats) == pytest.approx(10.0)


def test_fila_acumula_eta_e_posicao_por_worker() -> None:
    running = _job(JobState.RUNNING, stage="separating", progress=50)
    first = _job(JobState.QUEUED)
    export = _job(JobState.QUEUED, kind=JobKind.EXPORT)
    second = _job(JobState.QUEUED)

    result = estimate_queue([running, first, export, second], {})

    assert result[running.id].position is None
    assert result[running.id].eta_s == 25
    assert (result[first.id].position, result[first.id].eta_s) == (1, 85)
    assert (result[second.id].position, result[second.id].eta_s) == (2, 145)
    # Export tem worker próprio: não espera o processamento.
    assert (result[export.id].position, result[export.id].eta_s) == (1, 5)
