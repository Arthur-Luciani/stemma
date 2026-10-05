"""Busca e download via yt-dlp (ADR 0004 e 0010).

- Busca: in-process (rápida, sem gravar nada), com timeout total numa thread à parte.
- Download: subprocess `python -m yt_dlp`, como o Demucs: timeout total de verdade e
  cancelamento matando o processo, mesmo se o yt-dlp travar antes do primeiro byte.

Erros do yt-dlp viram `AppError` com código estável e mensagem amigável; nunca são
engolidos como "nenhum resultado".
"""

import concurrent.futures
import logging
import re
import sys
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from yt_dlp import YoutubeDL

from app.domain.errors import AppError
from app.domain.text import guess_identity
from app.pipeline.proc import Attachable, BinaryNotFoundError, ProcessTimeoutError, run_process

logger = logging.getLogger(__name__)

SEARCH_LIMIT = 10
SEARCH_TIMEOUT_S = 45
SOCKET_TIMEOUT_S = 30
# Linha de progresso pedida ao yt-dlp: "[stemma] baixados/total/total_estimado".
_PROGRESS_TEMPLATE = (
    "download:[stemma] %(progress.downloaded_bytes)s/%(progress.total_bytes)s"
    "/%(progress.total_bytes_estimate)s"
)
_PROGRESS_RE = re.compile(r"\[stemma\] (\d+)/(\S+)/(\S+)")
# Buscas que estouram o timeout continuam nesta pool até o yt-dlp desistir sozinho.
_SEARCH_POOL = concurrent.futures.ThreadPoolExecutor(max_workers=4, thread_name_prefix="search")
SOURCE_STEM = "source"
# Preferência entre os arquivos baixados, se sobrar mais de um.
_AUDIO_EXTENSIONS = (".m4a", ".webm", ".opus", ".mp3", ".ogg", ".aac", ".wav", ".flac")


class Progress(Attachable, Protocol):
    """O pedaço do `JobContext` que o download usa."""

    def progress(self, percent: float) -> None: ...


@dataclass(frozen=True)
class SearchResult:
    source_url: str
    source_title: str
    source_channel: str | None
    duration_s: float | None
    thumbnail_url: str | None
    artist: str
    title: str


YdlFactory = Callable[[dict[str, Any]], Any]


class YtDlpClient:
    def __init__(
        self,
        *,
        js_runtimes: Sequence[str],
        cookie_file: Path | None,
        timeout: float,
        ydl_factory: YdlFactory = YoutubeDL,
        python: str = sys.executable,
        search_timeout: float = SEARCH_TIMEOUT_S,
    ) -> None:
        self.js_runtimes = list(js_runtimes)
        self.cookie_file = cookie_file
        self.timeout = timeout
        self.search_timeout = search_timeout
        self.python = python
        self._ydl_factory = ydl_factory

    # --- busca ---------------------------------------------------------------

    def search(self, query: str, limit: int = SEARCH_LIMIT) -> list[SearchResult]:
        query = query.strip()
        target = query if looks_like_url(query) else f"ytsearch{limit}:{query}"
        options = {**self._base_options(), "skip_download": True, "extract_flat": "in_playlist"}

        def extract() -> Any:
            with self._ydl_factory(options) as ydl:
                return ydl.extract_info(target, download=False)

        future = _SEARCH_POOL.submit(extract)
        try:
            info = future.result(timeout=self.search_timeout)
        except concurrent.futures.TimeoutError as exc:
            logger.warning("Busca no YouTube passou de %.0f s", self.search_timeout)
            raise _youtube_unavailable() from exc
        except Exception as exc:
            raise map_ytdlp_error(exc, searching=True) from exc
        if not isinstance(info, dict):
            return []
        entries = info.get("entries")
        items = entries if entries is not None else [info]
        results = [r for e in items if isinstance(e, dict) and (r := to_search_result(e))]
        return results[:limit]

    # --- download ------------------------------------------------------------

    def download(self, url: str, dest_dir: Path, ctx: Progress) -> Path:
        """Baixa o melhor áudio em `dest_dir/source.<ext>` e devolve o arquivo."""
        dest_dir.mkdir(parents=True, exist_ok=True)
        progress = _DownloadProgress()
        try:
            result = run_process(
                self.download_command(url, dest_dir),
                timeout=self.timeout,
                ctx=ctx,
                on_line=progress.feed,
                on_poll=lambda: ctx.progress(progress.percent),
                env={"PYTHONIOENCODING": "utf-8"},
                merge_output=True,
            )
        except ProcessTimeoutError as exc:
            raise AppError(
                "download_timeout", "O download demorou demais e foi interrompido."
            ) from exc
        except BinaryNotFoundError as exc:  # pragma: no cover - o Python do app sempre existe
            raise AppError("download_failed", "Não foi possível rodar o yt-dlp.", 500) from exc
        if not result.ok:
            raise map_ytdlp_error(error_lines(result.stderr_tail))
        found = find_downloaded(dest_dir)
        if found is None:
            raise AppError("download_failed", "O download terminou, mas nenhum áudio foi salvo.")
        ctx.progress(100)
        return found

    def download_command(self, url: str, dest_dir: Path) -> list[str]:
        cmd = [
            self.python,
            "-m",
            "yt_dlp",
            "--format",
            "bestaudio/best",
            "--output",
            str(dest_dir / f"{SOURCE_STEM}.%(ext)s"),
            "--no-playlist",
            "--force-overwrites",
            "--quiet",
            "--no-warnings",
            "--progress",
            "--newline",
            "--progress-template",
            _PROGRESS_TEMPLATE,
            "--socket-timeout",
            str(SOCKET_TIMEOUT_S),
            # Só os runtimes da config, na ordem dela.
            "--no-js-runtimes",
        ]
        for runtime in self.js_runtimes:
            cmd += ["--js-runtimes", runtime]
        if self.cookie_file is not None:
            cmd += ["--cookies", str(self.cookie_file)]
        return [*cmd, "--", url]

    # --- interno -------------------------------------------------------------

    def _base_options(self) -> dict[str, Any]:
        options: dict[str, Any] = {
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "socket_timeout": SOCKET_TIMEOUT_S,
            "logger": _YdlLogger(),
            "js_runtimes": {name: {} for name in self.js_runtimes},
        }
        if self.cookie_file is not None:
            options["cookiefile"] = str(self.cookie_file)
        return options


class _DownloadProgress:
    """Lê as linhas de progresso do template (na thread leitora do subprocess)."""

    def __init__(self) -> None:
        self.percent = 0.0

    def feed(self, line: str) -> None:
        match = _PROGRESS_RE.search(line)
        if match is None:
            return
        done = int(match.group(1))
        total = _int_or_none(match.group(2)) or _int_or_none(match.group(3))
        if total:
            self.percent = max(self.percent, min(99.0, 100 * done / total))


class _YdlLogger:
    def debug(self, msg: str) -> None:
        if not msg.startswith("[download]"):
            logger.debug(msg)

    def info(self, msg: str) -> None:
        logger.debug(msg)

    def warning(self, msg: str) -> None:
        logger.warning("yt-dlp: %s", msg)

    def error(self, msg: str) -> None:
        logger.error("yt-dlp: %s", msg)


# --- funções puras -------------------------------------------------------------


def looks_like_url(text: str) -> bool:
    return text.startswith(("http://", "https://"))


def to_search_result(entry: dict[str, Any]) -> SearchResult | None:
    source_title = str(entry.get("title") or "").strip()
    video_id = str(entry.get("id") or "").strip()
    url = str(entry.get("webpage_url") or "").strip()
    if not url:
        raw = str(entry.get("url") or "").strip()
        url = raw if looks_like_url(raw) else ""
    if not url and video_id:
        url = f"https://www.youtube.com/watch?v={video_id}"
    if not source_title or not url:
        return None
    channel = str(entry.get("channel") or entry.get("uploader") or "").strip() or None
    duration = entry.get("duration")
    artist, title = guess_identity(source_title, channel)
    return SearchResult(
        source_url=url,
        source_title=source_title,
        source_channel=channel,
        duration_s=float(duration) if isinstance(duration, int | float) and duration > 0 else None,
        thumbnail_url=_thumbnail(entry, video_id),
        artist=artist,
        title=title,
    )


def find_downloaded(dest_dir: Path) -> Path | None:
    files = [
        f
        for f in dest_dir.glob(f"{SOURCE_STEM}.*")
        if f.is_file() and f.stat().st_size > 0 and not f.name.endswith((".part", ".ytdl"))
    ]
    if not files:
        return None
    files.sort(
        key=lambda f: (
            _AUDIO_EXTENSIONS.index(f.suffix) if f.suffix in _AUDIO_EXTENSIONS else 99,
            -f.stat().st_mtime,
        )
    )
    return files[0]


_AGE_KEYS = ("confirm your age", "age-restricted", "age restricted", "inappropriate for some users")
# Formato recusado costuma ser o desafio JS do YouTube falhando (runtime ausente ou
# yt-dlp desatualizado), não o vídeo indisponível.
_FORMAT_KEYS = ("requested format is not available", "no video formats found")
_UNAVAILABLE_KEYS = (
    "private video",
    "video unavailable",
    "video is not available",
    "has been removed",
    "unsupported url",
    "is not a valid url",
    "does not exist",
)
_LOGIN_KEYS = ("sign in", "cookies", "login required")
_NETWORK_KEYS = ("unable to download", "timed out", "connection", "getaddrinfo", "http error 5")


def map_ytdlp_error(error: BaseException | str, *, searching: bool = False) -> AppError:
    message = str(error).lower()
    logger.warning("yt-dlp falhou: %s", error)
    if any(key in message for key in _FORMAT_KEYS):
        return AppError(
            "youtube_format_unavailable",
            "O YouTube não liberou o áudio. Atualize o yt-dlp e confira o runtime JS no /health.",
            502,
        )
    if any(key in message for key in _AGE_KEYS):
        return AppError(
            "age_restricted",
            "Este vídeo tem restrição de idade. Atualize os cookies do YouTube.",
            422,
        )
    if any(key in message for key in _UNAVAILABLE_KEYS):
        return AppError(
            "video_unavailable",
            "Este vídeo não está disponível (privado, removido ou bloqueado).",
            422,
        )
    if any(key in message for key in _LOGIN_KEYS):
        return AppError("youtube_login_required", "YouTube pediu login. Atualize os cookies.", 503)
    if searching or any(key in message for key in _NETWORK_KEYS):
        return _youtube_unavailable()
    return AppError("download_failed", "Não foi possível baixar o áudio deste vídeo.", 502)


def error_lines(output: str) -> str:
    """As linhas `ERROR:` da saída do yt-dlp (ou a saída toda, se não houver)."""
    errors = [line for line in output.splitlines() if line.startswith("ERROR:")]
    return "\n".join(errors) or output


def _youtube_unavailable() -> AppError:
    return AppError(
        "youtube_unavailable", "Não deu para falar com o YouTube agora. Tente de novo.", 502
    )


def _int_or_none(text: str) -> int | None:
    try:
        return int(float(text))
    except ValueError:
        return None


def _thumbnail(entry: dict[str, Any], video_id: str) -> str | None:
    thumb = entry.get("thumbnail")
    if isinstance(thumb, str) and thumb:
        return thumb
    thumbs = entry.get("thumbnails")
    if isinstance(thumbs, list):
        urls = [t.get("url") for t in thumbs if isinstance(t, dict) and t.get("url")]
        if urls:
            return str(urls[-1])
    if (
        video_id
        and "youtube" in str(entry.get("ie_key") or entry.get("extractor") or "youtube").lower()
    ):
        return f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
    return None
