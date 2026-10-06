import json
import sys
import urllib.error
from collections.abc import Iterator
from datetime import timedelta
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app import __version__
from app.cli import main
from app.config import Settings, get_settings
from app.db.models import SystemUpdateModel
from app.db.types import utcnow
from app.domain.enums import UpdateState
from app.domain.releases import format_version, parse_version
from app.pipeline.updater import FAILURE_TTL_S, GitHubReleases, UpdateTask, UpdateTaskError
from app.services.system_update import RUNNING_TIMEOUT, record_update_result
from tests.conftest import open_db, process_session

CURRENT = parse_version(__version__)
assert CURRENT is not None
NEXT = format_version((CURRENT[0], CURRENT[1] + 1, 0))
AFTER_NEXT = format_version((CURRENT[0], CURRENT[1] + 1, 1))
OLDER = format_version((CURRENT[0], CURRENT[1], CURRENT[2] - 1) if CURRENT[2] else (0, 0, 1))


def release(
    version: str, *, installer: bool = True, body: str = "", **extra: Any
) -> dict[str, Any]:
    tag = f"v{version}"
    assets = [{"name": f"stemma-{tag}.zip"}]
    if installer:
        assets += [{"name": f"Stemma-Setup-{tag}.exe"}, {"name": f"Stemma-Setup-{tag}.exe.sha256"}]
    return {
        "tag_name": tag,
        "draft": False,
        "prerelease": False,
        "body": body,
        "published_at": "2026-10-06T18:00:00Z",
        "assets": assets,
        **extra,
    }


class FakeGitHub:
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
        super().__init__("schtasks", "\\Stemma\\Atualizar" if configured else "")
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


def releases_of(data: Any, clock: Clock | None = None) -> GitHubReleases:
    return GitHubReleases("x/y", ttl_s=3600, fetch=FakeGitHub(data), clock=clock or Clock())


@pytest.fixture
def task(client: TestClient) -> FakeTask:
    fake = FakeTask()
    client.app.state.update_task = fake  # type: ignore[attr-defined]
    return fake


def use_releases(client: TestClient, data: Any) -> None:
    client.app.state.releases = releases_of(data)  # type: ignore[attr-defined]


def last_row(client: TestClient) -> SystemUpdateModel | None:
    with open_db(client) as db:
        return db.scalar(select(SystemUpdateModel).order_by(SystemUpdateModel.id.desc()))


# --- GitHubReleases -------------------------------------------------------------


def test_releases_usa_cache_ate_o_ttl() -> None:
    clock = Clock()
    fetch = FakeGitHub([release(NEXT)])
    releases = GitHubReleases("x/y", ttl_s=3600, fetch=fetch, clock=clock)

    assert releases.list() is not None
    clock.now = 3599
    releases.list()
    assert fetch.calls == 1
    clock.now = 3601
    releases.list()
    assert fetch.calls == 2


def test_falha_de_rede_e_cacheada_por_pouco_tempo() -> None:
    clock = Clock()
    fetch = FakeGitHub(urllib.error.URLError("sem rede"))
    releases = GitHubReleases("x/y", ttl_s=3600, fetch=fetch, clock=clock)

    assert releases.list() is None
    clock.now = FAILURE_TTL_S - 1
    assert releases.list() is None
    assert fetch.calls == 1
    fetch.data = [release(NEXT)]
    clock.now = FAILURE_TTL_S + 1
    assert releases.list() is not None


def test_releases_ignora_rascunho_pre_release_e_tag_estranha() -> None:
    listing = releases_of(
        [
            release("9.0.0", draft=True),
            release("8.0.0", prerelease=True),
            {"tag_name": "nightly", "assets": []},
            "lixo",
            release(NEXT, installer=False),
            release(OLDER),
        ]
    ).list()

    assert listing is not None
    assert [(format_version(r.version), r.has_installer) for r in listing.releases] == [
        (NEXT, False),
        (OLDER, True),
    ]


def test_resposta_que_nao_e_lista_conta_como_indisponivel() -> None:
    assert releases_of({"message": "API rate limit exceeded"}).list() is None


def test_update_task_sem_nome_nao_roda() -> None:
    with pytest.raises(UpdateTaskError, match="não está configurada"):
        UpdateTask("schtasks", "").run()


def test_update_task_codigo_de_saida_vira_erro() -> None:
    # O Python recusa os argumentos `/run /tn …` e sai com código 2.
    task = UpdateTask(sys.executable, "\\Stemma\\Atualizar")
    with pytest.raises(UpdateTaskError):
        task.run()


def test_update_task_sem_binario() -> None:
    with pytest.raises(UpdateTaskError, match="não encontrado"):
        UpdateTask("schtasks-que-nao-existe", "\\Stemma\\Atualizar").run()


# --- GET /api/system/update -----------------------------------------------------


def test_status_com_versao_nova_e_notas_acumuladas(client: TestClient, task: FakeTask) -> None:
    use_releases(
        client,
        [
            release(AFTER_NEXT, body="### Bug Fixes\n\n* conserto ([#2](u))"),
            release(NEXT, body="### Features\n\n* **app:** atualizar pelo app"),
            release(__version__, body="### Features\n\n* já instalada"),
            release("99.0.0", installer=False, body="### Features\n\n* sem instalador ainda"),
        ],
    )

    body = client.get("/api/system/update").json()

    assert body["current_version"] == __version__
    assert body["check"] == "ok"
    assert body["checked_at"] is not None
    assert body["latest_version"] == AFTER_NEXT
    assert body["available"] is True
    assert body["can_update"] is True
    assert body["active_jobs"] == 0
    assert body["last_run"] is None
    assert body["notes"] == [
        {"version": AFTER_NEXT, "sections": [{"title": "Correções", "items": ["conserto"]}]},
        {
            "version": NEXT,
            "sections": [{"title": "Novidades", "items": ["app: atualizar pelo app"]}],
        },
    ]


def test_status_sem_novidade(client: TestClient, task: FakeTask) -> None:
    use_releases(client, [release(__version__), release(OLDER)])

    body = client.get("/api/system/update").json()

    assert body["available"] is False
    assert body["latest_version"] == __version__
    assert body["notes"] == []


def test_status_sem_rede_nunca_da_500(client: TestClient, task: FakeTask) -> None:
    use_releases(client, TimeoutError("timeout"))

    response = client.get("/api/system/update")

    assert response.status_code == 200
    body = response.json()
    assert body["check"] == "unavailable"
    assert body["available"] is False
    assert body["latest_version"] is None


def test_status_sem_tarefa(client: TestClient) -> None:
    client.app.state.update_task = FakeTask(configured=False)  # type: ignore[attr-defined]
    use_releases(client, [release(NEXT)])

    assert client.get("/api/system/update").json()["can_update"] is False


# --- POST /api/system/update ----------------------------------------------------


def test_iniciar_grava_running_e_dispara_a_tarefa(client: TestClient, task: FakeTask) -> None:
    use_releases(client, [release(NEXT)])

    response = client.post("/api/system/update")

    assert response.status_code == 202
    body = response.json()
    assert body["state"] == "running"
    assert body["from_version"] == __version__
    assert body["target_version"] == NEXT
    assert task.runs == 1
    assert client.get("/api/system/update").json()["last_run"]["state"] == "running"


def test_recusa_se_ja_houver_uma_em_andamento(client: TestClient, task: FakeTask) -> None:
    use_releases(client, [release(NEXT)])
    client.post("/api/system/update")

    response = client.post("/api/system/update")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "update_running"
    assert task.runs == 1


def test_recusa_com_job_ativo(client: TestClient, task: FakeTask) -> None:
    use_releases(client, [release(NEXT)])
    client.app.state.job_runner.stop()  # type: ignore[attr-defined]  # o job fica na fila
    process_session(client)

    response = client.post("/api/system/update")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "jobs_active"
    assert client.get("/api/system/update").json()["active_jobs"] == 1
    assert task.runs == 0
    assert last_row(client) is None


def test_recusa_sem_versao_nova(client: TestClient, task: FakeTask) -> None:
    use_releases(client, [release(__version__)])

    response = client.post("/api/system/update")

    assert response.status_code == 409
    assert response.json()["error"] == {
        "code": "update_unavailable",
        "message": "O Stemma já está na versão mais recente.",
    }


def test_recusa_sem_tarefa(client: TestClient) -> None:
    client.app.state.update_task = FakeTask(configured=False)  # type: ignore[attr-defined]
    use_releases(client, [release(NEXT)])

    response = client.post("/api/system/update")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "update_not_supported"


def test_recusa_sem_rede(client: TestClient, task: FakeTask) -> None:
    use_releases(client, urllib.error.URLError("sem rede"))

    response = client.post("/api/system/update")

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "update_check_failed"


def test_schtasks_falhando_vira_falha_gravada(client: TestClient) -> None:
    client.app.state.update_task = FakeTask(error="Acesso negado.")  # type: ignore[attr-defined]
    use_releases(client, [release(NEXT)])

    response = client.post("/api/system/update")

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "update_start_failed"
    row = last_row(client)
    assert row is not None
    assert row.state == UpdateState.FAILED
    assert row.message == "Não foi possível iniciar a atualização: Acesso negado."
    assert row.finished_at is not None


def test_running_velho_vira_falha_e_libera_nova_tentativa(
    client: TestClient, task: FakeTask
) -> None:
    use_releases(client, [release(NEXT)])
    with open_db(client) as db:
        db.add(
            SystemUpdateModel(
                from_version=__version__,
                target_version=NEXT,
                state=UpdateState.RUNNING,
                created_at=utcnow() - RUNNING_TIMEOUT - timedelta(minutes=1),
            )
        )
        db.commit()

    last = client.get("/api/system/update").json()["last_run"]
    assert last["state"] == "failed"
    assert "não terminou" in last["message"]
    assert client.post("/api/system/update").status_code == 202


# --- resultado (CLI, no fim da tarefa) ------------------------------------------


@pytest.fixture
def cli_env(monkeypatch: pytest.MonkeyPatch, migrated: Settings) -> Iterator[None]:
    monkeypatch.setenv("STORAGE_ROOT", str(migrated.storage_root))
    monkeypatch.setenv("DATABASE_URL", migrated.database_url)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_cli_grava_a_falha_com_o_motivo(client: TestClient, task: FakeTask, cli_env: None) -> None:
    use_releases(client, [release(NEXT)])
    client.post("/api/system/update")

    code = main(["update-result", "--state", "failed", "--message", "A v9 não subiu."])

    assert code == 0
    last = client.get("/api/system/update").json()["last_run"]
    assert last["state"] == "failed"
    assert last["message"] == "A v9 não subiu."
    assert last["finished_at"] is not None


def test_cli_grava_o_sucesso(client: TestClient, task: FakeTask, cli_env: None) -> None:
    use_releases(client, [release(NEXT)])
    client.post("/api/system/update")

    assert main(["update-result", "--state", "succeeded"]) == 0

    last = client.get("/api/system/update").json()["last_run"]
    assert last["state"] == "succeeded"
    assert last["message"] is None


def test_resultado_sem_pedido_nao_falha(client: TestClient) -> None:
    with open_db(client) as db:
        assert record_update_result(db, UpdateState.SUCCEEDED, None) is False
        with pytest.raises(ValueError):
            record_update_result(db, UpdateState.RUNNING, None)


def test_releases_de_um_arquivo_local(tmp_path: Path) -> None:
    """Ensaio: UPDATE_RELEASES_URL=file://… no lugar da API do GitHub."""
    listing = tmp_path / "releases.json"
    listing.write_text(json.dumps([release(NEXT)]), encoding="utf-8")

    result = GitHubReleases("x/y", ttl_s=60, url=listing.as_uri()).list()

    assert result is not None
    assert [format_version(r.version) for r in result.releases] == [NEXT]
