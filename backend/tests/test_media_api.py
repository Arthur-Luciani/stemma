import uuid

from fastapi.testclient import TestClient

from tests.audio_fixtures import needs_ffmpeg
from tests.conftest import create_session
from tests.pipeline_fakes import SECONDS, fakes, pipeline_client, ready_session

__all__ = ["fakes", "pipeline_client"]

pytestmark = needs_ffmpeg


def test_serve_stem_mp3_com_range(pipeline_client: TestClient) -> None:
    session = ready_session(pipeline_client)
    url = f"/api/sessions/{session['id']}/stems/vocals.mp3"

    full = pipeline_client.get(url)
    partial = pipeline_client.get(url, headers={"Range": "bytes=0-1023"})

    assert full.status_code == 200
    assert full.headers["content-type"] == "audio/mpeg"
    assert full.headers["accept-ranges"] == "bytes"
    assert full.headers["cache-control"] == "no-cache"
    assert partial.status_code == 206
    assert len(partial.content) == 1024
    assert partial.headers["content-range"] == f"bytes 0-1023/{len(full.content)}"
    assert partial.content == full.content[:1024]


def test_serve_peaks(pipeline_client: TestClient) -> None:
    session = ready_session(pipeline_client)

    response = pipeline_client.get(f"/api/sessions/{session['id']}/peaks/drums.json")

    assert response.status_code == 200
    body = response.json()
    assert body["duration_s"] == SECONDS
    assert all(0 <= p <= 1 for p in body["peaks"])


def test_stem_de_sessao_nao_pronta(pipeline_client: TestClient) -> None:
    session = create_session(pipeline_client)

    for url in (
        f"/api/sessions/{session['id']}/stems/vocals.mp3",
        f"/api/sessions/{session['id']}/peaks/vocals.json",
    ):
        response = pipeline_client.get(url)
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "stem_not_found"


def test_stem_invalido_e_sessao_inexistente(pipeline_client: TestClient) -> None:
    invalid = pipeline_client.get(f"/api/sessions/{uuid.uuid4()}/stems/piano.mp3")
    missing = pipeline_client.get(f"/api/sessions/{uuid.uuid4()}/stems/vocals.mp3")

    assert invalid.status_code == 422
    assert missing.status_code == 404
    assert missing.json()["error"]["code"] == "session_not_found"
