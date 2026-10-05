import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.db.models import JobModel, MixStateModel, SessionEventModel, SessionModel
from app.domain.enums import JobKind, JobState, SessionState
from tests.conftest import create_session, make_session_payload


def _set_state(db: Session, session_id: object, state: SessionState) -> None:
    db.execute(
        update(SessionModel)
        .where(SessionModel.id == uuid.UUID(str(session_id)))
        .values(state=state)
    )
    db.commit()


# --- criar -------------------------------------------------------------------


def test_cria_rascunho_com_codigo_sequencial(client: TestClient) -> None:
    first = create_session(client)
    second = create_session(client, title="Under Pressure")

    assert first["code"] == "ST-001"
    assert second["code"] == "ST-002"
    assert first["state"] == "draft"
    assert first["progress"] == 0
    assert first["stems"] == []
    assert first["artist"] == "Queen"
    assert first["source_url"] == "https://www.youtube.com/watch?v=abc123"
    created_at = datetime.fromisoformat(str(first["created_at"]))
    assert created_at.tzinfo is not None
    assert abs(datetime.now(UTC) - created_at) < timedelta(minutes=1)


def test_criar_registra_evento(client: TestClient, db: Session) -> None:
    created = create_session(client)

    events = db.scalars(
        select(SessionEventModel).where(
            SessionEventModel.session_id == uuid.UUID(str(created["id"]))
        )
    ).all()

    assert [(e.type, e.payload) for e in events] == [("created", {"code": "ST-001"})]


def test_codigo_nao_e_reaproveitado_apos_excluir(client: TestClient) -> None:
    first = create_session(client)
    client.delete(f"/api/sessions/{first['id']}")

    assert create_session(client)["code"] == "ST-002"


def test_criar_apara_espacos(client: TestClient) -> None:
    created = create_session(client, artist="  Queen ", title=" Bohemian Rhapsody  ")

    assert (created["artist"], created["title"]) == ("Queen", "Bohemian Rhapsody")


@pytest.mark.parametrize(
    ("overrides", "field"),
    [
        ({"artist": "   "}, "artist"),
        ({"title": ""}, "title"),
        ({"source_url": "nao-e-url"}, "source_url"),
        ({"source_url": "ftp://x.com/a"}, "source_url"),
        ({"duration_s": -1}, "duration_s"),
        ({"artist": "x" * 201}, "artist"),
        ({"extra": 1}, "extra"),
    ],
)
def test_criar_valida_entrada(client: TestClient, overrides: dict[str, object], field: str) -> None:
    response = client.post("/api/sessions", json=make_session_payload(**overrides))

    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "validation_error"
    assert field in error["message"]


def test_criar_sem_campos_obrigatorios(client: TestClient) -> None:
    response = client.post("/api/sessions", json={})

    assert response.status_code == 422
    assert "obrigatório" in response.json()["error"]["message"]


# --- obter / editar ----------------------------------------------------------


def test_obtem_sessao(client: TestClient) -> None:
    created = create_session(client)

    response = client.get(f"/api/sessions/{created['id']}")

    assert response.status_code == 200
    assert response.json() == created


def test_sessao_inexistente_404(client: TestClient) -> None:
    response = client.get(f"/api/sessions/{uuid.uuid4()}")

    assert response.status_code == 404
    assert response.json() == {
        "error": {"code": "session_not_found", "message": "Sessão não encontrada."}
    }


def test_id_invalido_422(client: TestClient) -> None:
    response = client.get("/api/sessions/ST-001")

    assert response.status_code == 422
    assert response.json()["error"] == {
        "code": "validation_error",
        "message": "Dados inválidos — session_id: identificador inválido.",
    }


def test_rota_inexistente_no_formato_padrao(client: TestClient) -> None:
    response = client.get("/api/nada")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_edita_artista_e_titulo(client: TestClient, db: Session) -> None:
    created = create_session(client)

    response = client.patch(
        f"/api/sessions/{created['id']}", json={"artist": "Queen & David Bowie"}
    )

    assert response.status_code == 200
    body = response.json()
    assert body["artist"] == "Queen & David Bowie"
    assert body["title"] == "Bohemian Rhapsody"
    event = db.scalars(
        select(SessionEventModel).where(SessionEventModel.type == "identity_updated")
    ).one()
    assert event.payload["after"]["artist"] == "Queen & David Bowie"
    # A busca passa a achar pela identidade nova.
    found = client.get("/api/sessions", params={"q": "bowie"}).json()
    assert [s["id"] for s in found["items"]] == [created["id"]]


@pytest.mark.parametrize("body", [{}, {"artist": " "}, {"state": "ready"}])
def test_edicao_invalida(client: TestClient, body: dict[str, object]) -> None:
    created = create_session(client)

    response = client.patch(f"/api/sessions/{created['id']}", json=body)

    assert response.status_code == 422


def test_editar_inexistente_404(client: TestClient) -> None:
    response = client.patch(f"/api/sessions/{uuid.uuid4()}", json={"title": "x"})

    assert response.status_code == 404


# --- listar ------------------------------------------------------------------


def test_lista_vazia(client: TestClient) -> None:
    body = client.get("/api/sessions").json()

    assert body["items"] == []
    assert body["total"] == 0
    assert body["counts"] == dict.fromkeys(
        ["draft", "queued", "downloading", "separating", "ready", "failed"], 0
    )


def test_lista_busca_sem_acento_e_por_codigo(client: TestClient) -> None:
    legiao = create_session(client, artist="Legião Urbana", title="Tempo Perdido")
    create_session(client, artist="Queen", title="Bohemian Rhapsody")

    by_text = client.get("/api/sessions", params={"q": "legiao tempo"}).json()
    by_code = client.get("/api/sessions", params={"q": "ST-001"}).json()
    nothing = client.get("/api/sessions", params={"q": "zzz"}).json()

    assert [s["id"] for s in by_text["items"]] == [legiao["id"]]
    assert [s["id"] for s in by_code["items"]] == [legiao["id"]]
    assert nothing["items"] == []
    assert nothing["total"] == 0


def test_lista_filtra_por_estado_com_contagens(client: TestClient, db: Session) -> None:
    a = create_session(client, title="A")
    b = create_session(client, title="B")
    c = create_session(client, title="C")
    _set_state(db, a["id"], SessionState.READY)
    _set_state(db, b["id"], SessionState.QUEUED)
    _set_state(db, c["id"], SessionState.SEPARATING)

    body = client.get("/api/sessions", params=[("state", "queued"), ("state", "separating")]).json()

    assert sorted(s["title"] for s in body["items"]) == ["B", "C"]
    assert body["total"] == 2
    # Contagens ignoram o filtro de estado (para os chips de filtro).
    assert body["counts"]["ready"] == 1
    assert body["counts"]["queued"] == 1
    assert body["counts"]["separating"] == 1
    assert body["counts"]["draft"] == 0


def test_contagens_respeitam_a_busca(client: TestClient) -> None:
    create_session(client, artist="Queen", title="A")
    create_session(client, artist="Oasis", title="B")

    body = client.get("/api/sessions", params={"q": "oasis"}).json()

    assert body["counts"]["draft"] == 1


def test_estado_invalido_422(client: TestClient) -> None:
    response = client.get("/api/sessions", params={"state": "pronto"})

    assert response.status_code == 422


@pytest.mark.parametrize(
    ("sort", "expected"),
    [
        ("newest", ["c", "b", "a"]),
        ("oldest", ["a", "b", "c"]),
        ("title", ["a", "b", "c"]),
        ("artist", ["b", "c", "a"]),
        ("longest", ["c", "a", "b"]),
        ("shortest", ["a", "c", "b"]),
    ],
)
def test_lista_ordenacao(client: TestClient, sort: str, expected: list[str]) -> None:
    create_session(client, title="a", artist="Zeca", duration_s=100)
    create_session(client, title="b", artist="abba", duration_s=None)
    create_session(client, title="c", artist="Beatles", duration_s=300)

    body = client.get("/api/sessions", params={"sort": sort}).json()

    assert [s["title"] for s in body["items"]] == expected


def test_lista_paginada(client: TestClient) -> None:
    for i in range(5):
        create_session(client, title=f"t{i}")

    page = client.get("/api/sessions", params={"limit": 2, "offset": 2, "sort": "oldest"}).json()

    assert [s["title"] for s in page["items"]] == ["t2", "t3"]
    assert page["total"] == 5


@pytest.mark.parametrize("params", [{"limit": 0}, {"limit": 101}, {"offset": -1}])
def test_paginacao_invalida(client: TestClient, params: dict[str, int]) -> None:
    assert client.get("/api/sessions", params=params).status_code == 422


# --- excluir -----------------------------------------------------------------


def test_exclui_sessao_arquivos_e_dependentes(
    client: TestClient, db: Session, migrated_storage: Path
) -> None:
    created = create_session(client)
    session_id = uuid.UUID(str(created["id"]))
    folder = migrated_storage / "sessions" / str(session_id)
    (folder / "stems").mkdir(parents=True)
    (folder / "stems" / "vocals.mp3").write_bytes(b"x")
    client.put(f"/api/sessions/{session_id}/mix", json=_any_mix())
    db.add(JobModel(kind=JobKind.PROCESS, session_id=session_id, state=JobState.DONE))
    db.commit()

    response = client.delete(f"/api/sessions/{session_id}")

    assert response.status_code == 204
    assert not folder.exists()
    assert not (migrated_storage / ".trash" / str(session_id)).exists()
    assert client.get(f"/api/sessions/{session_id}").status_code == 404
    for model in (MixStateModel, JobModel, SessionEventModel):
        assert db.scalar(select(func.count()).select_from(model)) == 0


def test_exclui_sessao_sem_pasta(client: TestClient) -> None:
    created = create_session(client)

    assert client.delete(f"/api/sessions/{created['id']}").status_code == 204


@pytest.mark.parametrize("state", [JobState.QUEUED, JobState.RUNNING])
def test_nao_exclui_com_job_ativo(
    client: TestClient, db: Session, migrated_storage: Path, state: JobState
) -> None:
    created = create_session(client)
    session_id = uuid.UUID(str(created["id"]))
    folder = migrated_storage / "sessions" / str(session_id)
    folder.mkdir(parents=True)
    db.add(JobModel(kind=JobKind.PROCESS, session_id=session_id, state=state))
    db.commit()

    response = client.delete(f"/api/sessions/{session_id}")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "session_busy"
    assert folder.exists()
    assert client.get(f"/api/sessions/{session_id}").status_code == 200


def test_falha_no_commit_devolve_a_pasta(
    client: TestClient, migrated_storage: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    created = create_session(client)
    folder = migrated_storage / "sessions" / str(created["id"])
    folder.mkdir(parents=True)

    def boom(self: Session) -> None:
        raise RuntimeError("disco cheio")

    monkeypatch.setattr(Session, "commit", boom)
    # Sem relançar no teste: queremos ver a resposta 500 que o cliente recebe.
    response = TestClient(client.app, raise_server_exceptions=False).delete(
        f"/api/sessions/{created['id']}"
    )
    monkeypatch.undo()

    assert response.status_code == 500
    assert response.json()["error"]["code"] == "internal_error"
    assert folder.exists()
    assert client.get(f"/api/sessions/{created['id']}").status_code == 200


def test_excluir_inexistente_404(client: TestClient) -> None:
    assert client.delete(f"/api/sessions/{uuid.uuid4()}").status_code == 404


def _any_mix() -> dict[str, object]:
    stem = {"volume": 50, "pan": 0, "mute": False, "solo": False}
    return {
        "stems": {s: stem for s in ("vocals", "drums", "bass", "other")},
        "preset": "custom",
    }
