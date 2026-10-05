from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.domain.enums import JobKind, JobState, SessionState
from app.main import create_app, default_job_handlers
from app.pipeline.fake import FakeProcessHandler
from tests.conftest import job_row, job_state, process_session, session_row
from tests.fakes import wait_until


@pytest.fixture
def fake_client(migrated: Settings) -> Iterator[TestClient]:
    handlers = {JobKind.PROCESS: FakeProcessHandler(total_seconds=0.3, tick_s=0.02)}
    with TestClient(create_app(migrated, job_handlers=handlers)) as client:
        yield client


def test_flag_liga_o_pipeline_falso(settings: Settings) -> None:
    assert default_job_handlers(settings) == {}
    settings.stemma_fake_pipeline = True
    assert isinstance(default_job_handlers(settings)[JobKind.PROCESS], FakeProcessHandler)


def test_pipeline_falso_passa_pelas_etapas_ate_pronta(fake_client: TestClient) -> None:
    job = process_session(fake_client)

    wait_until(lambda: job_state(fake_client, job["id"]) is JobState.DONE)

    row = job_row(fake_client, job["id"])
    session = session_row(fake_client, job["session_id"])
    assert row.stage_durations is not None
    assert set(row.stage_durations) == {"downloading", "separating"}
    assert (session.state, session.progress) == (SessionState.READY, 100)


def test_pipeline_falso_falha_com_marcador_no_titulo(fake_client: TestClient) -> None:
    job = process_session(fake_client, title="Teste [falha]")

    wait_until(lambda: job_state(fake_client, job["id"]) is JobState.FAILED)

    session = session_row(fake_client, job["session_id"])
    assert (session.state, session.error_code) == (SessionState.FAILED, "fake_failure")
    assert job_row(fake_client, job["id"]).stage is SessionState.SEPARATING
