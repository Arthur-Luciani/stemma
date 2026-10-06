"""Atualização pelo app (ADR 0015): consulta às releases do GitHub e disparo da tarefa
agendada que roda o instalador. Aqui só há I/O; as regras ficam no `SystemUpdateService`."""

import json
import logging
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from app import __version__
from app.db.types import utcnow
from app.domain.releases import Version, parse_version
from app.pipeline.proc import BinaryNotFoundError, ProcessTimeoutError, run_process

logger = logging.getLogger(__name__)

# Uma consulta que falhou vale por pouco tempo: a rede pode voltar logo.
FAILURE_TTL_S = 300.0


@dataclass(frozen=True)
class Release:
    version: Version
    tag: str
    body: str
    published_at: datetime | None
    # O job `installer` do release.yml anexa o `.exe` minutos depois da release.
    has_installer: bool


@dataclass(frozen=True)
class ReleaseList:
    releases: list[Release]
    checked_at: datetime


Fetch = Callable[[str, float], Any]


def _fetch_json(url: str, timeout: float) -> Any:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": f"stemma/{__version__}",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


class GitHubReleases:
    """Releases publicadas (sem rascunho nem pré-release), com cache em memória.

    O cache guarda só a resposta do GitHub (dado externo), não estado do app (ADR 0015)."""

    def __init__(
        self,
        repo: str,
        *,
        ttl_s: float,
        url: str = "",
        timeout_s: float = 5.0,
        fetch: Fetch = _fetch_json,
        clock: Callable[[], float] = time.monotonic,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self.url = url or f"https://api.github.com/repos/{repo}/releases?per_page=30"
        self.ttl_s = ttl_s
        self.timeout_s = timeout_s
        self._fetch = fetch
        self._clock = clock
        self._now = now
        self._lock = threading.Lock()
        self._cached: ReleaseList | None = None
        self._expires_at = 0.0

    def list(self) -> ReleaseList | None:
        """None = não foi possível consultar (rede, limite da API, resposta estranha)."""
        with self._lock:
            if self._clock() < self._expires_at:
                return self._cached
            result = self._load()
            self._cached = result
            self._expires_at = self._clock() + (self.ttl_s if result else FAILURE_TTL_S)
            return result

    def _load(self) -> ReleaseList | None:
        try:
            data = self._fetch(self.url, self.timeout_s)
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            logger.warning("Não foi possível consultar as releases: %s", exc)
            return None
        if not isinstance(data, list):
            logger.warning("Resposta inesperada do GitHub: %r", type(data))
            return None
        releases = [r for r in (_safe_parse(item) for item in data) if r is not None]
        return ReleaseList(releases, (self._now or utcnow)())


def _safe_parse(item: Any) -> Release | None:
    """Um item estranho (data inválida, campos trocados) é ignorado, não derruba a lista."""
    try:
        return _parse_release(item)
    except (ValueError, TypeError, AttributeError) as exc:
        logger.warning("Release ignorada (%s): %r", exc, item)
        return None


def _parse_release(item: Any) -> Release | None:
    if not isinstance(item, dict) or item.get("draft") or item.get("prerelease"):
        return None
    tag = str(item.get("tag_name", ""))
    version = parse_version(tag)
    if version is None:
        return None
    assets = item.get("assets") or []
    names = {str(asset.get("name")) for asset in assets if isinstance(asset, dict)}
    installer = f"Stemma-Setup-{tag}.exe"
    published = item.get("published_at")
    return Release(
        version=version,
        tag=tag,
        body=str(item.get("body") or ""),
        published_at=datetime.fromisoformat(published) if isinstance(published, str) else None,
        has_installer=installer in names and f"{installer}.sha256" in names,
    )


class UpdateTaskError(Exception):
    """A tarefa agendada não pôde ser disparada (mensagem já em PT-BR)."""


class UpdateTask:
    """Dispara a tarefa agendada `\\Stemma\\Atualizar` (`schtasks /run`). Nome vazio = sem
    tarefa (dev, CI, instalação antiga)."""

    def __init__(self, schtasks_bin: str, task_name: str, timeout_s: float = 30.0) -> None:
        self.schtasks_bin = schtasks_bin
        self.task_name = task_name
        self.timeout_s = timeout_s

    @property
    def configured(self) -> bool:
        return bool(self.task_name)

    def run(self) -> None:
        if not self.configured:
            raise UpdateTaskError("A tarefa de atualização não está configurada.")
        cmd = [self.schtasks_bin, "/run", "/tn", self.task_name]
        try:
            result = run_process(cmd, timeout=self.timeout_s, merge_output=True)
        except BinaryNotFoundError as exc:
            raise UpdateTaskError(f"{exc.binary} não encontrado.") from exc
        except ProcessTimeoutError as exc:
            raise UpdateTaskError(f"O agendador do Windows não respondeu ({exc}).") from exc
        if not result.ok:
            detail = " ".join(result.stderr_tail.split())
            logger.error("schtasks falhou (%s): %s", result.returncode, detail)
            raise UpdateTaskError(detail or f"schtasks terminou com código {result.returncode}.")
