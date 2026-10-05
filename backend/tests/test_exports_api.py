import uuid
from urllib.parse import unquote

from fastapi.testclient import TestClient

from app.domain.enums import JobState
from app.storage import Storage
from tests.audio_fixtures import needs_ffmpeg
from tests.conftest import create_session, job_row
from tests.fakes import wait_until
from tests.pipeline_fakes import fakes, pipeline_client, ready_session

__all__ = ["fakes", "pipeline_client"]

pytestmark = needs_ffmpeg

MIX_SEM_VOZ = {
    "vocals": {"volume": 100, "pan": 0, "mute": True, "solo": False},
    "drums": {"volume": 80, "pan": -0.5, "mute": False, "solo": False},
    "bass": {"volume": 100, "pan": 0, "mute": False, "solo": False},
    "other": {"volume": 100, "pan": 0.3, "mute": False, "solo": False},
}


def export_done(client: TestClient, session_id: object, export_id: object) -> dict[str, object]:
    """Espera o export terminar (pronto ou falho) e o devolve."""
    found: dict[str, object] = {}

    def finished() -> bool:
        items = client.get(f"/api/sessions/{session_id}/exports").json()["items"]
        found.update(next(e for e in items if e["id"] == export_id))
        return found["state"] in {"done", "failed"}

    wait_until(finished, timeout=20)
    return found


def test_exporta_mp3_com_o_mix_do_corpo_e_baixa(pipeline_client: TestClient) -> None:
    session = ready_session(pipeline_client, artist="Legião Urbana", title="Tempo Perdido")

    response = pipeline_client.post(
        f"/api/sessions/{session['id']}/exports",
        json={"format": "mp3", "preset": "no_vocals", "stems": MIX_SEM_VOZ},
    )

    assert response.status_code == 201, response.text
    created = response.json()
    assert created["state"] in {"queued", "running", "done"}
    assert created["file_name"] == "Legião Urbana - Tempo Perdido (Sem voz).mp3"
    assert created["stems"]["drums"]["volume"] == 80

    export = export_done(pipeline_client, session["id"], created["id"])
    assert export["state"] == "done"
    assert export["progress"] == 100
    assert isinstance(export["size_bytes"], int)
    assert export["size_bytes"] > 50_000
    assert export["lufs"] is not None

    download = pipeline_client.get(f"/api/exports/{created['id']}/file")
    assert download.status_code == 200
    assert download.headers["content-type"] == "audio/mpeg"
    assert len(download.content) == export["size_bytes"]
    disposition = unquote(download.headers["content-disposition"])
    assert "Legião Urbana - Tempo Perdido (Sem voz).mp3" in disposition


def test_exporta_wav_com_o_mix_salvo(pipeline_client: TestClient) -> None:
    session = ready_session(pipeline_client)
    pipeline_client.put(
        f"/api/sessions/{session['id']}/mix", json={"stems": MIX_SEM_VOZ, "preset": "custom"}
    )

    created = pipeline_client.post(
        f"/api/sessions/{session['id']}/exports", json={"format": "wav"}
    ).json()
    export = export_done(pipeline_client, session["id"], created["id"])

    assert export["preset"] == "custom"
    assert export["stems"] == MIX_SEM_VOZ
    assert export["file_name"] == "Queen - Bohemian Rhapsody (Personalizado).wav"
    download = pipeline_client.get(f"/api/exports/{created['id']}/file")
    assert download.headers["content-type"] == "audio/wav"
    assert download.content[:4] == b"RIFF"


def test_export_fica_fora_do_dock(pipeline_client: TestClient) -> None:
    session = ready_session(pipeline_client)
    created = pipeline_client.post(
        f"/api/sessions/{session['id']}/exports", json={"format": "wav"}
    ).json()
    export_done(pipeline_client, session["id"], created["id"])

    jobs = pipeline_client.get("/api/jobs").json()["items"]

    assert [j["kind"] for j in jobs] == ["process"]


def test_lista_exports_mais_recentes_primeiro(pipeline_client: TestClient) -> None:
    session = ready_session(pipeline_client)
    first = pipeline_client.post(
        f"/api/sessions/{session['id']}/exports", json={"format": "wav"}
    ).json()
    second = pipeline_client.post(
        f"/api/sessions/{session['id']}/exports", json={"format": "mp3"}
    ).json()

    items = pipeline_client.get(f"/api/sessions/{session['id']}/exports").json()["items"]

    assert [e["id"] for e in items] == [second["id"], first["id"]]


def test_export_de_sessao_nao_pronta(pipeline_client: TestClient) -> None:
    session = create_session(pipeline_client)

    response = pipeline_client.post(
        f"/api/sessions/{session['id']}/exports", json={"format": "wav"}
    )

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "session_not_ready"


def test_export_sem_stem_soando(pipeline_client: TestClient) -> None:
    session = ready_session(pipeline_client)
    mudo = {stem: {**level, "mute": True} for stem, level in MIX_SEM_VOZ.items()}

    response = pipeline_client.post(
        f"/api/sessions/{session['id']}/exports", json={"format": "wav", "stems": mudo}
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "no_active_stems"


def test_download_de_export_inexistente_ou_nao_pronto(pipeline_client: TestClient) -> None:
    missing = pipeline_client.get(f"/api/exports/{uuid.uuid4()}/file")
    assert missing.status_code == 404
    assert missing.json()["error"]["code"] == "export_not_found"


def test_export_com_stems_sumidos_falha(pipeline_client: TestClient) -> None:
    session = ready_session(pipeline_client)
    storage: Storage = pipeline_client.app.state.storage  # type: ignore[attr-defined]
    session_id = uuid.UUID(str(session["id"]))
    storage.resolve(Storage.stem_audio(session_id, "vocals")).unlink()

    created = pipeline_client.post(
        f"/api/sessions/{session['id']}/exports", json={"format": "wav"}
    ).json()
    export = export_done(pipeline_client, session["id"], created["id"])

    assert export["state"] == "failed"
    assert export["error_code"] == "stems_missing"
    jobs = [j for j in pipeline_client.get("/api/jobs").json()["items"] if j["kind"] == "export"]
    assert jobs == []


def test_cancelar_export_na_fila(pipeline_client: TestClient) -> None:
    session = ready_session(pipeline_client)
    runner = pipeline_client.app.state.job_runner  # type: ignore[attr-defined]
    runner.stop()  # ninguém pega o job: ele fica na fila
    created = pipeline_client.post(
        f"/api/sessions/{session['id']}/exports", json={"format": "wav"}
    ).json()
    job = next(j for j in pipeline_client.get("/api/jobs").json()["items"] if j["kind"] == "export")

    assert pipeline_client.delete(f"/api/jobs/{job['id']}").status_code == 204

    export = pipeline_client.get(f"/api/sessions/{session['id']}/exports").json()["items"][0]
    assert export["id"] == created["id"]
    assert export["state"] == "failed"
    assert export["error_code"] == "cancelled"
    assert job_row(pipeline_client, job["id"]).state is JobState.CANCELLED
    assert job_row(pipeline_client, job["id"]).dismissed_at is not None
