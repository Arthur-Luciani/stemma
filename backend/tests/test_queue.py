"""JobRunner: ordem, concorrência, recuperação, parada limpa, cancelamento e falhas."""

import uuid
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import update
from sqlalchemy.orm import Session

from app.config import Settings
from app.db.engine import make_engine
from app.db.models import JobModel, SessionModel
from app.domain.enums import JobKind, JobState, SessionState
from app.domain.errors import AppError
from app.main import create_app
from app.services import events as events_module
from tests.conftest import (
    create_session,
    job_row,
    job_state,
    open_db,
    process_session,
    session_row,
)
from tests.fakes import ControlledHandler, wait_until


def test_fila_em_ordem_e_um_job_por_vez_no_gpu(
    queue_client: TestClient, handler: ControlledHandler
) -> None:
    jobs = [process_session(queue_client, title=t) for t in ("um", "dois", "tres")]

    assert handler.next_started() == "um"
    items = queue_client.get("/api/jobs").json()["items"]
    assert [(j["session"]["title"], j["state"], j["position"]) for j in items] == [
        ("um", "running", None),
        ("dois", "queued", 1),
        ("tres", "queued", 2),
    ]

    handler.finish()
    assert handler.next_started() == "dois"
    handler.finish()
    assert handler.next_started() == "tres"
    handler.finish()
    wait_until(lambda: all(job_state(queue_client, j["id"]) is JobState.DONE for j in jobs))

    assert handler.max_running == 1
    session = session_row(queue_client, jobs[0]["session_id"])
    assert session.state is SessionState.READY
    assert session.progress == 100
    assert session.processed_at is not None


def test_worker_leve_roda_em_paralelo_ao_gpu(migrated: Settings) -> None:
    gpu, light = ControlledHandler(), ControlledHandler()
    app = create_app(migrated, job_handlers={JobKind.PROCESS: gpu, JobKind.EXPORT: light})
    with TestClient(app) as client:
        process_session(client, title="processo")
        assert gpu.next_started() == "processo"

        session = create_session(client, title="export")
        with open_db(client) as db:
            db.add(JobModel(kind=JobKind.EXPORT, session_id=uuid.UUID(str(session["id"]))))
            db.commit()
        app.state.job_runner.wake()

        assert light.next_started() == "export"
        # O export não mexe no estado da sessão (só o processamento mexe).
        assert session_row(client, session["id"]).state is SessionState.DRAFT
        gpu.finish()
        light.finish()


def _seed_running_job(settings: Settings, attempt: int) -> tuple[uuid.UUID, uuid.UUID]:
    """Simula um servidor que caiu no meio: sessão separando e job `running` no banco."""
    with TestClient(create_app(settings, job_handlers={})) as client:
        session = create_session(client, title="interrompida")
        session_id = uuid.UUID(str(session["id"]))
        with open_db(client) as db:
            job = JobModel(
                kind=JobKind.PROCESS,
                session_id=session_id,
                state=JobState.RUNNING,
                attempt=attempt,
                stage=SessionState.SEPARATING,
                progress=40.0,
            )
            db.add(job)
            db.execute(
                update(SessionModel)
                .where(SessionModel.id == session_id)
                .values(state=SessionState.SEPARATING, progress=40.0)
            )
            db.commit()
            return job.id, session_id


def test_recuperacao_reenfileira_job_interrompido(migrated: Settings) -> None:
    job_id, session_id = _seed_running_job(migrated, attempt=1)
    handler = ControlledHandler()

    with TestClient(create_app(migrated, job_handlers={JobKind.PROCESS: handler})) as client:
        assert handler.next_started() == "interrompida"
        assert job_row(client, job_id).attempt == 2
        handler.finish()
        wait_until(lambda: job_state(client, job_id) is JobState.DONE)
        assert session_row(client, session_id).state is SessionState.READY


def test_recuperacao_falha_apos_esgotar_tentativas(migrated: Settings) -> None:
    job_id, session_id = _seed_running_job(migrated, attempt=2)
    handler = ControlledHandler()

    with TestClient(create_app(migrated, job_handlers={JobKind.PROCESS: handler})) as client:
        job = job_row(client, job_id)
        session = session_row(client, session_id)

    assert job.state is JobState.FAILED
    assert job.error_code == "interrupted"
    assert session.state is SessionState.FAILED
    assert session.error_code == "interrupted"
    assert session.error_message == "O processamento foi interrompido. Tente de novo."
    assert handler.started.empty()


def test_parada_limpa_devolve_job_a_fila_sem_gastar_tentativa(migrated: Settings) -> None:
    handler = ControlledHandler()
    with TestClient(create_app(migrated, job_handlers={JobKind.PROCESS: handler})) as client:
        job = process_session(client)
        handler.next_started()
    # Saiu do `with`: o lifespan parou o runner com o job no meio.

    engine = make_engine(migrated.database_url)
    try:
        with Session(engine) as db:
            row = db.get(JobModel, uuid.UUID(str(job["id"])))
            session = db.get(SessionModel, uuid.UUID(str(job["session_id"])))
    finally:
        engine.dispose()
    assert row is not None and session is not None
    assert (row.state, row.attempt, row.stage) == (JobState.QUEUED, 0, None)
    assert (session.state, session.progress) == (SessionState.QUEUED, 0)
    assert handler.tasks[0].cancelled.is_set()


def test_cancelar_job_rodando(queue_client: TestClient, handler: ControlledHandler) -> None:
    first = process_session(queue_client, title="um")
    second = process_session(queue_client, title="dois")
    assert handler.next_started() == "um"

    response = queue_client.delete(f"/api/jobs/{first['id']}")

    assert response.status_code == 204
    assert handler.tasks[0].cancelled.is_set()
    assert handler.next_started() == "dois"
    assert job_state(queue_client, first["id"]) is JobState.CANCELLED
    session = session_row(queue_client, first["session_id"])
    assert session.state is SessionState.FAILED
    assert session.error_code == "cancelled"
    assert session.error_message == "Processamento cancelado."
    ids = [j["id"] for j in queue_client.get("/api/jobs").json()["items"]]
    assert first["id"] not in ids
    handler.finish()
    wait_until(lambda: job_state(queue_client, second["id"]) is JobState.DONE)


def test_cancelar_job_na_fila(queue_client: TestClient, handler: ControlledHandler) -> None:
    process_session(queue_client, title="um")
    queued = process_session(queue_client, title="dois")
    handler.next_started()

    assert queue_client.delete(f"/api/jobs/{queued['id']}").status_code == 204
    handler.finish()

    assert job_state(queue_client, queued["id"]) is JobState.CANCELLED
    assert session_row(queue_client, queued["session_id"]).error_code == "cancelled"
    assert handler.started.empty()


def test_cancelar_job_encerrado_409(queue_client: TestClient, handler: ControlledHandler) -> None:
    job = process_session(queue_client)
    handler.next_started()
    handler.finish()
    wait_until(lambda: job_state(queue_client, job["id"]) is JobState.DONE)

    response = queue_client.delete(f"/api/jobs/{job['id']}")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "job_not_active"


def test_runner_nao_sobrescreve_cancelamento(migrated: Settings) -> None:
    handler = ControlledHandler(ignore_cancel=True)
    with TestClient(create_app(migrated, job_handlers={JobKind.PROCESS: handler})) as client:
        job = process_session(client)
        handler.next_started()
        # Cancelamento gravado por fora do runner (corrida com o fim do job).
        with open_db(client) as db:
            db.execute(
                update(JobModel)
                .where(JobModel.id == uuid.UUID(str(job["id"])))
                .values(state=JobState.CANCELLED)
            )
            db.commit()
        handler.finish()
        wait_until(lambda: handler.running == 0)

        assert job_state(client, job["id"]) is JobState.CANCELLED
        assert session_row(client, job["session_id"]).state is not SessionState.READY


def _run_failing(client: TestClient, handler: ControlledHandler, exc: Exception) -> Any:
    job = process_session(client)
    handler.next_started()
    handler.fail(exc)
    wait_until(lambda: job_state(client, job["id"]) is JobState.FAILED)
    return job


def test_erro_do_handler_vira_falha_com_codigo(
    queue_client: TestClient, handler: ControlledHandler
) -> None:
    job = _run_failing(
        queue_client, handler, AppError("youtube_login_required", "YouTube pediu login.")
    )

    row = job_row(queue_client, job["id"])
    session = session_row(queue_client, job["session_id"])
    assert (row.error_code, row.error_message) == ("youtube_login_required", "YouTube pediu login.")
    assert (session.state, session.error_code) == (SessionState.FAILED, "youtube_login_required")


def test_erro_inesperado_vira_internal_error(
    queue_client: TestClient, handler: ControlledHandler
) -> None:
    job = _run_failing(queue_client, handler, RuntimeError("boom"))

    session = session_row(queue_client, job["session_id"])
    assert session.error_code == "internal_error"
    assert session.error_message == "Erro inesperado no processamento."


def test_sem_pipeline_o_job_falha_como_indisponivel(client: TestClient) -> None:
    job = process_session(client)

    wait_until(lambda: job_state(client, job["id"]) is JobState.FAILED)
    assert session_row(client, job["session_id"]).error_code == "pipeline_unavailable"


def test_progresso_e_etapa_gravados_no_job_e_na_sessao(
    queue_client: TestClient, handler: ControlledHandler
) -> None:
    job = process_session(queue_client)
    handler.next_started()

    row = job_row(queue_client, job["id"])
    session = session_row(queue_client, job["session_id"])
    assert (row.stage, row.progress, row.attempt) == (SessionState.DOWNLOADING, 50, 1)
    assert (session.state, session.progress) == (SessionState.DOWNLOADING, 50)

    handler.finish()
    wait_until(lambda: job_state(queue_client, job["id"]) is JobState.DONE)
    durations = job_row(queue_client, job["id"]).stage_durations
    assert durations is not None and set(durations) == {"downloading"}


def test_falha_ao_publicar_evento_nao_derruba_o_job(
    queue_client: TestClient, handler: ControlledHandler, monkeypatch: pytest.MonkeyPatch
) -> None:
    class BrokenEstimator:
        def __init__(self, _db: object) -> None:
            pass

        def estimate(self) -> None:
            raise RuntimeError("banco ocupado")

    # Só a publicação de eventos quebra; a rota continua respondendo.
    monkeypatch.setattr(events_module, "QueueEstimator", BrokenEstimator)
    job = process_session(queue_client)
    handler.next_started()
    handler.finish()

    wait_until(lambda: job_state(queue_client, job["id"]) is JobState.DONE)
    assert session_row(queue_client, job["session_id"]).state is SessionState.READY


def test_worker_sobrevive_a_erro_ao_encerrar_job(
    queue_client: TestClient, handler: ControlledHandler, monkeypatch: pytest.MonkeyPatch
) -> None:
    runner = queue_client.app.state.job_runner  # type: ignore[attr-defined]
    original = runner._finish
    calls = {"n": 0}

    def flaky_finish(*args: Any, **kwargs: Any) -> None:
        calls["n"] += 1
        if calls["n"] == 1:
            raise RuntimeError("database is locked")
        original(*args, **kwargs)

    monkeypatch.setattr(runner, "_finish", flaky_finish)
    process_session(queue_client, title="um")
    second = process_session(queue_client, title="dois")
    handler.next_started()
    handler.finish()

    # O worker continua vivo e pega o próximo job.
    assert handler.next_started() == "dois"
    handler.finish()
    wait_until(lambda: job_state(queue_client, second["id"]) is JobState.DONE)
