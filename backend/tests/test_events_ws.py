"""Eventos chegando pelo `/ws` depois de cada escrita."""

from collections.abc import Callable, Iterator
from typing import Any

import pytest
from fastapi.testclient import TestClient
from starlette.testclient import WebSocketTestSession

from app.config import Settings
from app.domain.enums import JobKind, JobState
from app.main import create_app
from app.pipeline.fake import FakeProcessHandler
from tests.conftest import create_session, job_state
from tests.fakes import wait_until

Event = dict[str, Any]


@pytest.fixture
def fake_client(migrated: Settings) -> Iterator[TestClient]:
    handlers = {JobKind.PROCESS: FakeProcessHandler(total_seconds=0.3, tick_s=0.02)}
    with TestClient(create_app(migrated, job_handlers=handlers)) as client:
        yield client


def receive_until(ws: WebSocketTestSession, predicate: Callable[[Event], bool]) -> list[Event]:
    """Lê eventos até um satisfazer `predicate`; devolve todos os lidos."""
    events: list[Event] = []
    for _ in range(1000):
        event: Event = ws.receive_json()
        events.append(event)
        if predicate(event):
            return events
    raise AssertionError("evento esperado não chegou")


def _session_state(event: Event) -> str | None:
    if event["type"] != "session.updated":
        return None
    state: str = event["data"]["session"]["state"]
    return state


def test_criar_editar_e_excluir_publicam_eventos(fake_client: TestClient) -> None:
    with fake_client.websocket_connect("/ws") as ws:
        session = create_session(fake_client)
        created = ws.receive_json()
        fake_client.patch(f"/api/sessions/{session['id']}", json={"title": "Outro"})
        patched = ws.receive_json()
        fake_client.delete(f"/api/sessions/{session['id']}")
        deleted = ws.receive_json()

    assert created["type"] == "session.updated"
    assert created["data"]["session"]["id"] == session["id"]
    assert patched["data"]["session"]["title"] == "Outro"
    assert deleted == {"type": "session.deleted", "data": {"id": session["id"]}}


def test_processamento_publica_etapas_progresso_e_fim(fake_client: TestClient) -> None:
    session = create_session(fake_client)
    with fake_client.websocket_connect("/ws") as ws:
        fake_client.post(f"/api/sessions/{session['id']}/process")
        events = receive_until(
            ws, lambda e: e["type"] == "job.updated" and e["data"]["job"]["state"] == "done"
        )

    # Cada evento traz o estado do banco na hora da publicação: o worker pode já ter pegado
    # o job quando o evento do enfileiramento é montado.
    states = [s for s in map(_session_state, events) if s]
    assert states[0] in ("queued", "downloading")
    assert "downloading" in states and "separating" in states
    assert states[-1] == "ready"
    assert states.index("downloading") < states.index("separating")

    jobs = [e["data"]["job"] for e in events if e["type"] == "job.updated"]
    assert jobs[0]["state"] in ("queued", "running")
    assert any(j["state"] == "running" and 0 < j["progress"] < 100 for j in jobs)
    assert jobs[-1]["state"] == "done"
    assert all(j["session"]["id"] == session["id"] for j in jobs)


def test_dois_clientes_recebem_os_mesmos_eventos(fake_client: TestClient) -> None:
    with fake_client.websocket_connect("/ws") as ws1, fake_client.websocket_connect("/ws") as ws2:
        session = create_session(fake_client)
        first, second = ws1.receive_json(), ws2.receive_json()

    assert first == second
    assert first["data"]["session"]["id"] == session["id"]


def test_openapi_inclui_os_tipos_dos_eventos(fake_client: TestClient) -> None:
    schemas = fake_client.get("/openapi.json").json()["components"]["schemas"]

    mapping = schemas["LiveEvent"]["discriminator"]["mapping"]
    assert set(mapping) == {"session.updated", "session.deleted", "job.updated"}
    assert "JobUpdatedEvent" in schemas


def test_descartar_publica_job_com_dismissed_at(fake_client: TestClient) -> None:
    session = create_session(fake_client, title="Teste [falha]")
    job = fake_client.post(f"/api/sessions/{session['id']}/process").json()
    wait_until(lambda: job_state(fake_client, job["id"]) is JobState.FAILED)

    with fake_client.websocket_connect("/ws") as ws:
        fake_client.post(f"/api/jobs/{job['id']}/discard")
        event = ws.receive_json()

    assert event["type"] == "job.updated"
    assert event["data"]["job"]["id"] == job["id"]
    assert event["data"]["job"]["dismissed_at"] is not None
