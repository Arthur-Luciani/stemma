"""Download e Demucs falsos que geram áudio sintético de verdade (ffmpeg), para testar o
pipeline real de ponta a ponta sem rede nem GPU."""

import threading
from collections.abc import Callable, Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.domain.enums import STEMS, JobKind, JobState
from app.domain.errors import AppError
from app.main import create_app
from app.pipeline.audio import Ffmpeg
from app.pipeline.download import Progress
from app.pipeline.handlers import ExportHandler, ProcessHandler
from app.pipeline.proc import Attachable
from app.pipeline.separate import Separation
from app.storage import Storage
from tests.audio_fixtures import FFMPEG, sine_wav
from tests.conftest import job_state, process_session
from tests.fakes import wait_until

SECONDS = 2.0
# Frequência de cada stem sintético (só para diferenciar os arquivos).
_FREQS = {"vocals": 440, "drums": 220, "bass": 110, "other": 660}


class FakeDownloader:
    def __init__(self) -> None:
        self.urls: list[str] = []
        self.error: AppError | None = None

    def download(self, url: str, dest_dir: Path, ctx: Progress) -> Path:
        self.urls.append(url)
        if self.error is not None:
            raise self.error
        ctx.progress(50)
        return sine_wav(dest_dir / "source.wav", seconds=SECONDS, volume=0.5)


class FakeSeparator:
    """Gera os 4 WAVs. Com `hold`, espera o teste liberar (para testar cancelamento)."""

    def __init__(self) -> None:
        self.hold = threading.Event()
        self.hold.set()
        self.started = threading.Event()

    def separate(
        self,
        source: Path,
        work_dir: Path,
        ctx: Attachable,
        on_progress: Callable[[float], None],
    ) -> Separation:
        self.started.set()
        while not self.hold.wait(0.02):
            if ctx.cancelled:
                from app.pipeline.queue import JobCancelledError

                raise JobCancelledError
        on_progress(50)
        out = work_dir / "demucs" / "htdemucs"
        stems = {
            stem: sine_wav(out / f"{stem.value}.wav", seconds=SECONDS, freq=_FREQS[stem.value])
            for stem in STEMS
        }
        on_progress(100)
        return Separation(stems, "cpu")


class PipelineFakes:
    def __init__(self) -> None:
        self.downloader = FakeDownloader()
        self.separator = FakeSeparator()


@pytest.fixture
def fakes() -> PipelineFakes:
    return PipelineFakes()


@pytest.fixture
def pipeline_client(migrated: Settings, fakes: PipelineFakes) -> Iterator[TestClient]:
    """App com os handlers reais, mas download e Demucs falsos."""
    storage = Storage(migrated.storage_root)
    ffmpeg = Ffmpeg(FFMPEG or "ffmpeg", timeout=60)
    handlers = {
        JobKind.PROCESS: ProcessHandler(storage, fakes.downloader, fakes.separator, ffmpeg),
        JobKind.EXPORT: ExportHandler(storage, ffmpeg),
    }
    with TestClient(create_app(migrated, job_handlers=handlers)) as client:
        yield client


def ready_session(client: TestClient, **overrides: object) -> dict[str, object]:
    """Processa uma sessão até ficar pronta; devolve a sessão."""
    job = process_session(client, **overrides)
    wait_until(lambda: job_state(client, job["id"]) is not JobState.QUEUED, timeout=10)
    wait_until(lambda: job_state(client, job["id"]) is not JobState.RUNNING, timeout=20)
    assert job_state(client, job["id"]) is JobState.DONE, client.get("/api/jobs").json()
    body: dict[str, object] = client.get(f"/api/sessions/{job['session_id']}").json()
    return body
