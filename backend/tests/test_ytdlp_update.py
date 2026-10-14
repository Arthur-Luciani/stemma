"""Atualização do yt-dlp pelo app e pela tarefa diária (ADR 0016)."""

import json
import urllib.error
from collections.abc import Iterator
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from yt_dlp.version import __version__ as ytdlp_version

from app.cli import main
from app.config import Settings, get_settings
from app.db.models import SystemUpdateModel
from app.db.types import utcnow
from app.domain.enums import UpdateComponent, UpdateState
from app.domain.releases import parse_ytdlp_version
from app.pipeline.updater import FAILURE_TTL_S, UpdateTask, UpdateTaskError, YtDlpReleases
from app.services.update_guard import RUNNING_TIMEOUTS
from app.services.ytdlp_update import STALE_AFTER, YtDlpUpdateService, record_ytdlp_result
from tests.conftest import create_session, open_db, process_session

INSTALLED = "2025.07.06"
NEWER = "2025.10.22"


def pypi(version: str = NEWER, *, published: datetime | None = None) -> dict[str, Any]:
    stamp = (published or utcnow()).isoformat().replace("+00:00", "Z")
    return {
        "info": {"version": version},
        "urls": [
            {"filename": "yt_dlp.whl", "upload_time_iso_8601": stamp},
            {"filename": "yt_dlp.tar.gz", "upload_time_iso_8601": "lixo"},
        ],
    }


class FakePyPI:
    def __init__(self, data: Any) -> None:
        self.data = data
        self.calls = 0

    def __call__(self, url: str, timeout: float) -> Any:
        self.calls += 1
        if isinstance(self.data, Exception):
            raise self.data
        return self.data


class FakeTask(UpdateTask):
    def __init__(self, *, configured: bool = True, error: str | None = None) -> None:
        super().__init__("schtasks", "\\Stemma\\AtualizarYtDlp" if configured else "")
        self.error = error
        self.runs = 0

    def run(self) -> None:
        self.runs += 1
        if self.error:
            raise UpdateTaskError(self.error)


class Clock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def releases_of(data: Any, clock: Clock | None = None) -> YtDlpReleases:
    return YtDlpReleases(ttl_s=3600, fetch=FakePyPI(data), clock=clock or Clock())


@pytest.fixture
def task(client: TestClient) -> FakeTask:
    fake = FakeTask()
    client.app.state.ytdlp_update_task = fake  # type: ignore[attr-defined]
    return fake


@pytest.fixture(autouse=True)
def installed(monkeypatch: pytest.MonkeyPatch) -> None:
    """Versão "instalada" fixa: os testes não dependem do yt-dlp do lock."""
    original = YtDlpUpdateService.__init__

    def init(self: YtDlpUpdateService, *args: Any, **kwargs: Any) -> None:
        kwargs.setdefault("installed_version", INSTALLED)
        original(self, *args, **kwargs)

    monkeypatch.setattr(YtDlpUpdateService, "__init__", init)


def use_pypi(client: TestClient, data: Any) -> None:
    client.app.state.ytdlp_releases = releases_of(data)  # type: ignore[attr-defined]


def last_row(client: TestClient) -> SystemUpdateModel | None:
    with open_db(client) as db:
        return db.scalar(select(SystemUpdateModel).order_by(SystemUpdateModel.id.desc()))


def add_run(
    client: TestClient,
    component: UpdateComponent,
    *,
    state: UpdateState = UpdateState.RUNNING,
    age: timedelta = timedelta(0),
) -> None:
    with open_db(client) as db:
        db.add(
            SystemUpdateModel(
                component=component,
                from_version="x",
                target_version="y",
                state=state,
                created_at=utcnow() - age,
            )
        )
        db.commit()


# --- versões e PyPI ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("2025.07.06", (2025, 7, 6)),
        ("2025.7.6", (2025, 7, 6)),
        ("2025.10.22.1", (2025, 10, 22, 1)),
        (" 2025.10.22 ", (2025, 10, 22)),
        ("2025.10", None),
        ("2025.10.22.dev0", None),
        ("v2025.10.22", None),
    ],
)
def test_parse_ytdlp_version(text: str, expected: tuple[int, ...] | None) -> None:
    assert parse_ytdlp_version(text) == expected


def test_pypi_le_versao_e_data_e_usa_cache() -> None:
    clock = Clock()
    published = datetime(2025, 10, 22, 18, 0, tzinfo=utcnow().tzinfo)
    fetch = FakePyPI(pypi(published=published))
    releases = YtDlpReleases(ttl_s=3600, fetch=fetch, clock=clock)

    latest = releases.latest()

    assert latest is not None
    assert latest.version == NEWER
    assert latest.published_at == published
    clock.now = 3599
    releases.latest()
    assert fetch.calls == 1
    clock.now = 3601
    releases.latest()
    assert fetch.calls == 2


def test_pypi_falha_e_cacheada_por_pouco_tempo() -> None:
    clock = Clock()
    fetch = FakePyPI(urllib.error.URLError("sem rede"))
    releases = YtDlpReleases(ttl_s=3600, fetch=fetch, clock=clock)

    assert releases.latest() is None
    clock.now = FAILURE_TTL_S - 1
    assert releases.latest() is None
    assert fetch.calls == 1
    fetch.data = pypi()
    clock.now = FAILURE_TTL_S + 1
    assert releases.latest() is not None


@pytest.mark.parametrize(
    "data", [{"message": "not found"}, {"info": {"version": "nightly"}}, ["lixo"]]
)
def test_pypi_resposta_estranha_conta_como_indisponivel(data: Any) -> None:
    assert releases_of(data).latest() is None


def test_pypi_de_um_arquivo_local(tmp_path: Path) -> None:
    """Ensaio: YTDLP_RELEASES_URL=file://… no lugar do PyPI."""
    listing = tmp_path / "yt-dlp.json"
    listing.write_text(json.dumps(pypi()), encoding="utf-8")

    latest = YtDlpReleases(ttl_s=60, url=listing.as_uri()).latest()

    assert latest is not None
    assert latest.version == NEWER


# --- GET /api/system/ytdlp ---------------------------------------------------------


def test_status_com_versao_nova(client: TestClient, task: FakeTask) -> None:
    use_pypi(client, pypi())

    body = client.get("/api/system/ytdlp").json()

    assert body["installed_version"] == INSTALLED
    assert body["check"] == "ok"
    assert body["checked_at"] is not None
    assert body["latest_version"] == NEWER
    assert body["latest_published_at"] is not None
    assert body["available"] is True
    assert body["stale"] is False
    assert body["can_update"] is True
    assert body["active_jobs"] == 0
    assert body["last_run"] is None


def test_status_atrasado_depois_de_dias(client: TestClient, task: FakeTask) -> None:
    use_pypi(client, pypi(published=utcnow() - STALE_AFTER - timedelta(hours=1)))

    assert client.get("/api/system/ytdlp").json()["stale"] is True


def test_status_em_dia_compara_numeros_e_nao_texto(client: TestClient, task: FakeTask) -> None:
    # O PyPI publica sem zeros à esquerda; o pacote instalado tem.
    use_pypi(client, pypi("2025.7.6", published=utcnow() - timedelta(days=30)))

    body = client.get("/api/system/ytdlp").json()

    assert body["available"] is False
    assert body["stale"] is False


def test_status_sem_rede_nunca_da_500(client: TestClient, task: FakeTask) -> None:
    use_pypi(client, TimeoutError("timeout"))

    response = client.get("/api/system/ytdlp")

    assert response.status_code == 200
    body = response.json()
    assert body["check"] == "unavailable"
    assert body["available"] is False
    assert body["latest_version"] is None


def test_status_sem_tarefa(client: TestClient) -> None:
    client.app.state.ytdlp_update_task = FakeTask(configured=False)  # type: ignore[attr-defined]
    use_pypi(client, pypi())

    assert client.get("/api/system/ytdlp").json()["can_update"] is False


# --- POST /api/system/ytdlp --------------------------------------------------------


def test_iniciar_grava_running_e_dispara_a_tarefa(client: TestClient, task: FakeTask) -> None:
    use_pypi(client, pypi())

    response = client.post("/api/system/ytdlp")

    assert response.status_code == 202
    body = response.json()
    assert body["state"] == "running"
    assert body["from_version"] == INSTALLED
    assert body["target_version"] == NEWER
    assert task.runs == 1
    row = last_row(client)
    assert row is not None
    assert row.component == UpdateComponent.YTDLP
    assert client.get("/api/system/ytdlp").json()["last_run"]["state"] == "running"
    # A do Stemma não enxerga a do yt-dlp como sua.
    assert client.get("/api/system/update").json()["last_run"] is None


def test_recusa_se_ja_houver_uma_em_andamento(client: TestClient, task: FakeTask) -> None:
    use_pypi(client, pypi())
    client.post("/api/system/ytdlp")

    response = client.post("/api/system/ytdlp")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "update_running"
    assert task.runs == 1


def test_recusa_com_atualizacao_do_stemma_em_andamento(client: TestClient, task: FakeTask) -> None:
    use_pypi(client, pypi())
    add_run(client, UpdateComponent.APP)

    response = client.post("/api/system/ytdlp")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "update_running"
    assert task.runs == 0


def test_stemma_recusa_atualizar_com_ytdlp_em_andamento(client: TestClient) -> None:
    add_run(client, UpdateComponent.YTDLP)

    response = client.post("/api/system/update")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "update_running"


def test_recusa_com_job_ativo(client: TestClient, task: FakeTask) -> None:
    use_pypi(client, pypi())
    client.app.state.job_runner.stop()  # type: ignore[attr-defined]  # o job fica na fila
    process_session(client)

    response = client.post("/api/system/ytdlp")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "jobs_active"
    assert client.get("/api/system/ytdlp").json()["active_jobs"] == 1
    assert task.runs == 0
    assert last_row(client) is None


def test_recusa_sem_versao_nova(client: TestClient, task: FakeTask) -> None:
    use_pypi(client, pypi(INSTALLED))

    response = client.post("/api/system/ytdlp")

    assert response.status_code == 409
    assert response.json()["error"] == {
        "code": "update_unavailable",
        "message": "O yt-dlp já está na versão mais recente.",
    }


def test_recusa_sem_tarefa(client: TestClient) -> None:
    client.app.state.ytdlp_update_task = FakeTask(configured=False)  # type: ignore[attr-defined]
    use_pypi(client, pypi())

    response = client.post("/api/system/ytdlp")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "update_not_supported"


def test_recusa_sem_rede(client: TestClient, task: FakeTask) -> None:
    use_pypi(client, urllib.error.URLError("sem rede"))

    response = client.post("/api/system/ytdlp")

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "update_check_failed"


def test_schtasks_falhando_vira_falha_gravada(client: TestClient) -> None:
    client.app.state.ytdlp_update_task = FakeTask(error="Acesso negado.")  # type: ignore[attr-defined]
    use_pypi(client, pypi())

    response = client.post("/api/system/ytdlp")

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "update_start_failed"
    row = last_row(client)
    assert row is not None
    assert row.state == UpdateState.FAILED
    assert row.message == "Não foi possível iniciar a atualização do yt-dlp: Acesso negado."


def test_running_velho_vira_falha_e_libera_nova_tentativa(
    client: TestClient, task: FakeTask
) -> None:
    use_pypi(client, pypi())
    add_run(
        client,
        UpdateComponent.YTDLP,
        age=RUNNING_TIMEOUTS[UpdateComponent.YTDLP] + timedelta(minutes=1),
    )

    last = client.get("/api/system/ytdlp").json()["last_run"]
    assert last["state"] == "failed"
    assert "não terminou" in last["message"]
    assert client.post("/api/system/ytdlp").status_code == 202


def test_atualizando_o_ytdlp_recusa_processar(client: TestClient, task: FakeTask) -> None:
    use_pypi(client, pypi())
    session = create_session(client)
    client.post("/api/system/ytdlp")

    response = client.post(f"/api/sessions/{session['id']}/process")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "update_running"


# --- tarefa agendada (CLI) ----------------------------------------------------------


@pytest.fixture
def cli_env(monkeypatch: pytest.MonkeyPatch, migrated: Settings, tmp_path: Path) -> Iterator[Path]:
    """O CLI lê o PyPI de um arquivo (`YTDLP_RELEASES_URL`), escrito pelo teste."""
    listing = tmp_path / "pypi.json"
    listing.write_text(json.dumps(pypi()), encoding="utf-8")
    monkeypatch.setenv("STORAGE_ROOT", str(migrated.storage_root))
    monkeypatch.setenv("DATABASE_URL", migrated.database_url)
    monkeypatch.setenv("YTDLP_RELEASES_URL", listing.as_uri())
    get_settings.cache_clear()
    yield listing
    get_settings.cache_clear()


def begin(capsys: pytest.CaptureFixture[str]) -> str:
    capsys.readouterr()
    assert main(["ytdlp-begin"]) == 0
    return capsys.readouterr().out.strip()


def test_tarefa_pedida_pelo_app_instala_a_versao_gravada(
    client: TestClient, task: FakeTask, cli_env: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    use_pypi(client, pypi())
    client.post("/api/system/ytdlp")
    # O PyPI andou depois do pedido: a tarefa instala o que o app mostrou.
    cli_env.write_text(json.dumps(pypi("2025.11.1")), encoding="utf-8")

    assert begin(capsys) == f"run|{INSTALLED}|{NEWER}"
    with open_db(client) as db:
        assert len(db.scalars(select(SystemUpdateModel)).all()) == 1


def test_tarefa_diaria_com_versao_nova_grava_running(
    client: TestClient, cli_env: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert begin(capsys) == f"run|{INSTALLED}|{NEWER}"

    row = last_row(client)
    assert row is not None
    assert row.component == UpdateComponent.YTDLP
    assert row.state == UpdateState.RUNNING
    assert row.target_version == NEWER
    # Rodar de novo (tarefa repetida) segue a mesma, sem criar outra.
    assert begin(capsys) == f"run|{INSTALLED}|{NEWER}"


def test_tarefa_diaria_sem_versao_nova_pula(
    client: TestClient, cli_env: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    cli_env.write_text(json.dumps(pypi(INSTALLED)), encoding="utf-8")

    assert begin(capsys) == f"skip|o yt-dlp {INSTALLED} já é o mais recente"
    assert last_row(client) is None


def test_tarefa_diaria_com_job_ativo_pula(
    client: TestClient, cli_env: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    client.app.state.job_runner.stop()  # type: ignore[attr-defined]
    process_session(client)

    assert begin(capsys) == "skip|há 1 job(s) na fila ou rodando"
    assert last_row(client) is None


def test_tarefa_diaria_com_stemma_atualizando_pula(
    client: TestClient, cli_env: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    add_run(client, UpdateComponent.APP)

    assert begin(capsys) == "skip|há uma atualização do Stemma em andamento"


def test_tarefa_diaria_sem_rede_pula(
    client: TestClient, cli_env: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    cli_env.unlink()

    assert begin(capsys) == "skip|não foi possível consultar o PyPI"


def test_cli_grava_o_resultado(
    client: TestClient, cli_env: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    begin(capsys)

    assert main(["ytdlp-result", "--state", "failed", "--message", "O serviço não voltou."]) == 0

    row = last_row(client)
    assert row is not None
    assert row.state == UpdateState.FAILED
    assert row.message == "O serviço não voltou."
    assert row.finished_at is not None


def test_resultado_nao_mexe_na_atualizacao_do_stemma(client: TestClient) -> None:
    add_run(client, UpdateComponent.APP)
    with open_db(client) as db:
        assert record_ytdlp_result(db, UpdateState.SUCCEEDED, None) is False
    row = last_row(client)
    assert row is not None
    assert row.state == UpdateState.RUNNING


def test_versao_do_ytdlp_instalado_e_comparavel() -> None:
    assert parse_ytdlp_version(ytdlp_version) is not None
