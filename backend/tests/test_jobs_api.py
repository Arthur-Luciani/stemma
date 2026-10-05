"""Rotas da fila: process, reprocess, GET /api/jobs, cancelar e descartar."""

from fastapi.testclient import TestClient

from app.domain.enums import JobState
from tests.conftest import create_session, job_state, process_session
from tests.fakes import ControlledHandler, wait_until

MISSING = "00000000-0000-0000-0000-000000000000"


def _finish_ok(client: TestClient, handler: ControlledHandler, job: dict[str, object]) -> None:
    handler.next_started()
    handler.finish()
    wait_until(lambda: job_state(client, job["id"]) is JobState.DONE)


def test_process_enfileira_rascunho(queue_client: TestClient, handler: ControlledHandler) -> None:
    session = create_session(queue_client)

    response = queue_client.post(f"/api/sessions/{session['id']}/process")

    assert response.status_code == 201
    job = response.json()
    assert job["kind"] == "process"
    assert job["session_id"] == session["id"]
    assert job["session"]["code"] == session["code"]
    assert job["state"] in ("queued", "running")
    handler.next_started()
    handler.finish()


def test_process_recusa_sessao_que_nao_e_rascunho(
    queue_client: TestClient, handler: ControlledHandler
) -> None:
    job = process_session(queue_client)

    response = queue_client.post(f"/api/sessions/{job['session_id']}/process")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "session_not_draft"
    _finish_ok(queue_client, handler, job)


def test_process_404_e_422(queue_client: TestClient) -> None:
    missing = queue_client.post(f"/api/sessions/{MISSING}/process")
    invalid = queue_client.post("/api/sessions/nao-e-uuid/process")

    assert missing.status_code == 404
    assert missing.json()["error"]["code"] == "session_not_found"
    assert invalid.status_code == 422


def test_reprocess_recusa_rascunho(queue_client: TestClient) -> None:
    session = create_session(queue_client)

    response = queue_client.post(f"/api/sessions/{session['id']}/reprocess")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "session_not_processed"


def test_reprocess_recusa_com_job_ativo(
    queue_client: TestClient, handler: ControlledHandler
) -> None:
    job = process_session(queue_client)

    response = queue_client.post(f"/api/sessions/{job['session_id']}/reprocess")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "session_busy"
    _finish_ok(queue_client, handler, job)


def test_reprocess_de_sessao_pronta_e_de_falha(
    queue_client: TestClient, handler: ControlledHandler
) -> None:
    job = process_session(queue_client)
    _finish_ok(queue_client, handler, job)

    again = queue_client.post(f"/api/sessions/{job['session_id']}/reprocess")
    assert again.status_code == 201
    handler.next_started()
    handler.fail(RuntimeError("boom"))
    wait_until(lambda: job_state(queue_client, again.json()["id"]) is JobState.FAILED)

    third = queue_client.post(f"/api/sessions/{job['session_id']}/reprocess")
    assert third.status_code == 201
    # Os jobs encerrados anteriores da sessão saem do dock.
    ids = [j["id"] for j in queue_client.get("/api/jobs").json()["items"]]
    assert ids == [third.json()["id"]]
    _finish_ok(queue_client, handler, third.json())


def test_lista_jobs_com_posicao_eta_e_encerrados(
    queue_client: TestClient, handler: ControlledHandler
) -> None:
    done = process_session(queue_client, title="pronta", duration_s=100.0)
    _finish_ok(queue_client, handler, done)
    running = process_session(queue_client, title="rodando", duration_s=100.0)
    handler.next_started()
    queued = process_session(queue_client, title="na fila", duration_s=100.0)

    items = queue_client.get("/api/jobs").json()["items"]

    assert [j["id"] for j in items] == [running["id"], queued["id"], done["id"]]
    current, waiting, finished = items
    assert (current["state"], current["stage"], current["progress"]) == (
        "running",
        "downloading",
        50,
    )
    assert current["position"] is None
    assert waiting["position"] == 1
    assert isinstance(current["eta_s"], int) and isinstance(waiting["eta_s"], int)
    assert waiting["eta_s"] > current["eta_s"]
    assert (finished["state"], finished["eta_s"], finished["position"]) == ("done", None, None)
    handler.finish()
    handler.next_started()
    handler.finish()


def test_descartar_job_encerrado(queue_client: TestClient, handler: ControlledHandler) -> None:
    job = process_session(queue_client)
    handler.next_started()
    handler.fail(RuntimeError("boom"))
    wait_until(lambda: job_state(queue_client, job["id"]) is JobState.FAILED)

    response = queue_client.post(f"/api/jobs/{job['id']}/discard")

    assert response.status_code == 204
    assert queue_client.get("/api/jobs").json()["items"] == []
    # A sessão continua "Falhou" na Biblioteca.
    session = queue_client.get(f"/api/sessions/{job['session_id']}").json()
    assert session["state"] == "failed"
    again = queue_client.post(f"/api/jobs/{job['id']}/discard")
    assert again.status_code == 409


def test_descartar_job_ativo_409(queue_client: TestClient, handler: ControlledHandler) -> None:
    job = process_session(queue_client)

    response = queue_client.post(f"/api/jobs/{job['id']}/discard")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "job_not_dismissable"
    _finish_ok(queue_client, handler, job)


def test_jobs_404_e_422(queue_client: TestClient) -> None:
    for method, path in (
        ("DELETE", f"/api/jobs/{MISSING}"),
        ("POST", f"/api/jobs/{MISSING}/discard"),
    ):
        response = queue_client.request(method, path)
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "job_not_found"
    assert queue_client.delete("/api/jobs/123").status_code == 422


def test_excluir_sessao_exige_cancelar_antes(
    queue_client: TestClient, handler: ControlledHandler
) -> None:
    job = process_session(queue_client)
    handler.next_started()

    busy = queue_client.delete(f"/api/sessions/{job['session_id']}")
    assert busy.status_code == 409
    assert busy.json()["error"]["code"] == "session_busy"

    assert queue_client.delete(f"/api/jobs/{job['id']}").status_code == 204
    assert queue_client.delete(f"/api/sessions/{job['session_id']}").status_code == 204
    assert queue_client.get("/api/jobs").json()["items"] == []
