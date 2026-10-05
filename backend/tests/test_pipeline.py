"""Job de processamento real (handlers de verdade + ffmpeg), com download e Demucs falsos."""

import json
import uuid

from fastapi.testclient import TestClient

from app.domain.enums import JobState, SessionState
from app.domain.errors import AppError
from app.storage import Storage
from tests.audio_fixtures import needs_ffmpeg
from tests.conftest import job_row, job_state, process_session, session_row
from tests.fakes import wait_until
from tests.pipeline_fakes import SECONDS, PipelineFakes, fakes, pipeline_client, ready_session

__all__ = ["fakes", "pipeline_client"]

pytestmark = needs_ffmpeg


def storage_of(client: TestClient) -> Storage:
    storage: Storage = client.app.state.storage  # type: ignore[attr-defined]
    return storage


def test_processa_ate_pronta_com_stems_peaks_e_metricas(
    pipeline_client: TestClient, fakes: PipelineFakes
) -> None:
    session = ready_session(pipeline_client, duration_s=None)
    session_id = uuid.UUID(str(session["id"]))
    storage = storage_of(pipeline_client)

    assert session["state"] == "ready"
    assert session["stems"] == ["vocals", "drums", "bass", "other"]
    metrics = session["metrics"]
    assert isinstance(metrics, dict)
    assert metrics["lufs"] is not None
    assert metrics["true_peak_db"] is not None
    # Duração real, medida na decodificação (a sessão veio sem duração).
    assert session["duration_s"] == SECONDS
    assert fakes.downloader.urls == ["https://www.youtube.com/watch?v=abc123"]

    row = session_row(pipeline_client, session_id)
    assert row.stems == {
        stem: f"sessions/{session_id}/stems/{stem}.mp3"
        for stem in ("vocals", "drums", "bass", "other")
    }
    peaks = json.loads(storage.resolve(Storage.stem_peaks(session_id, "bass")).read_text())
    assert peaks["duration_s"] == SECONDS
    assert len(peaks["peaks"]) == 1600
    # Sobras do processamento são apagadas.
    assert not storage.resolve(Storage.raw_dir(session_id)).exists()
    assert not storage.resolve(Storage.work_dir(session_id)).exists()


def test_etapas_e_progresso_no_job(pipeline_client: TestClient) -> None:
    session = ready_session(pipeline_client)
    job = next(
        j
        for j in pipeline_client.get("/api/jobs").json()["items"]
        if j["session_id"] == session["id"]
    )
    row = job_row(pipeline_client, job["id"])

    assert row.stage is SessionState.SEPARATING
    assert set(row.stage_durations or {}) == {"downloading", "separating"}


def test_reprocessar_troca_os_stems(pipeline_client: TestClient, fakes: PipelineFakes) -> None:
    session = ready_session(pipeline_client)
    session_id = uuid.UUID(str(session["id"]))
    storage = storage_of(pipeline_client)
    stale = storage.resolve(Storage.stems_dir(session_id)) / "sobra.mp3"
    stale.write_bytes(b"x")
    fakes.separator.hold.clear()
    fakes.separator.started.clear()

    job = pipeline_client.post(f"/api/sessions/{session_id}/reprocess").json()
    assert fakes.separator.started.wait(10)

    # Durante o reprocessamento, os stems antigos já saíram.
    assert not stale.exists()
    assert pipeline_client.get(f"/api/sessions/{session_id}").json()["stems"] == []
    fakes.separator.hold.set()
    wait_until(lambda: job_state(pipeline_client, job["id"]) is JobState.DONE, timeout=20)
    assert pipeline_client.get(f"/api/sessions/{session_id}").json()["stems"] == [
        "vocals",
        "drums",
        "bass",
        "other",
    ]


def test_falha_no_download_marca_a_sessao(
    pipeline_client: TestClient, fakes: PipelineFakes
) -> None:
    fakes.downloader.error = AppError(
        "youtube_login_required", "YouTube pediu login. Atualize os cookies."
    )

    job = process_session(pipeline_client)
    wait_until(lambda: job_state(pipeline_client, job["id"]) is JobState.FAILED, timeout=10)

    session = session_row(pipeline_client, job["session_id"])
    assert session.state is SessionState.FAILED
    assert session.error_code == "youtube_login_required"
    assert session.error_message == "YouTube pediu login. Atualize os cookies."
    assert not storage_of(pipeline_client).resolve(Storage.raw_dir(session.id)).exists()


def test_cancelar_na_separacao(pipeline_client: TestClient, fakes: PipelineFakes) -> None:
    fakes.separator.hold.clear()
    job = process_session(pipeline_client)
    assert fakes.separator.started.wait(10)

    assert pipeline_client.delete(f"/api/jobs/{job['id']}").status_code == 204

    wait_until(lambda: job_state(pipeline_client, job["id"]) is JobState.CANCELLED)
    session = session_row(pipeline_client, job["session_id"])
    assert session.error_code == "cancelled"
    storage = storage_of(pipeline_client)
    # O `finally` do handler apaga as sobras logo depois do cancelamento.
    wait_until(lambda: not storage.resolve(Storage.raw_dir(session.id)).exists())
    assert not storage.resolve(Storage.stems_dir(session.id)).exists()
