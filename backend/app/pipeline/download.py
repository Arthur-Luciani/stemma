"""Busca e download via yt-dlp (in-process, ADR 0004).

Erros do yt-dlp viram `AppError` com código estável e mensagem amigável; nunca são
engolidos como "nenhum resultado".
"""

import logging
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from yt_dlp import YoutubeDL

from app.domain.errors import AppError
from app.domain.text import guess_identity
from app.pipeline.queue import JobCancelledError

logger = logging.getLogger(__name__)

SEARCH_LIMIT = 10
SOCKET_TIMEOUT_S = 30
SOURCE_STEM = "source"
# Preferência entre os arquivos baixados, se sobrar mais de um.
_AUDIO_EXTENSIONS = (".m4a", ".webm", ".opus", ".mp3", ".ogg", ".aac", ".wav", ".flac")


class Progress(Protocol):
    """O pedaço do `JobContext` que o download usa."""

    @property
    def cancelled(self) -> bool: ...

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
    ) -> None:
        self.js_runtimes = list(js_runtimes)
        self.cookie_file = cookie_file
        self.timeout = timeout
        self._ydl_factory = ydl_factory

    # --- busca ---------------------------------------------------------------

    def search(self, query: str, limit: int = SEARCH_LIMIT) -> list[SearchResult]:
        query = query.strip()
        target = query if looks_like_url(query) else f"ytsearch{limit}:{query}"
        options = {**self._base_options(), "skip_download": True, "extract_flat": "in_playlist"}
        try:
            with self._ydl_factory(options) as ydl:
                info = ydl.extract_info(target, download=False)
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
        deadline = time.monotonic() + self.timeout

        def hook(status: dict[str, Any]) -> None:
            if ctx.cancelled:
                raise JobCancelledError
            if time.monotonic() > deadline:
                raise _DownloadTimeoutError
            if status.get("status") == "downloading":
                total = status.get("total_bytes") or status.get("total_bytes_estimate")
                done = status.get("downloaded_bytes") or 0
                if total:
                    ctx.progress(min(99.0, 100 * done / total))

        options = {
            **self._base_options(),
            "format": "bestaudio/best",
            "outtmpl": str(dest_dir / f"{SOURCE_STEM}.%(ext)s"),
            "overwrites": True,
            "noprogress": True,
            "progress_hooks": [hook],
        }
        try:
            with self._ydl_factory(options) as ydl:
                ydl.extract_info(url, download=True)
        except Exception as exc:
            if ctx.cancelled or _caused_by(exc, JobCancelledError):
                raise JobCancelledError from exc
            if _caused_by(exc, _DownloadTimeoutError):
                raise AppError(
                    "download_timeout", "O download demorou demais e foi interrompido."
                ) from exc
            raise map_ytdlp_error(exc) from exc
        found = find_downloaded(dest_dir)
        if found is None:
            raise AppError("download_failed", "O download terminou, mas nenhum áudio foi salvo.")
        ctx.progress(100)
        return found

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


class _DownloadTimeoutError(Exception):
    pass


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
_UNAVAILABLE_KEYS = (
    "private video",
    "video unavailable",
    "not available",
    "has been removed",
    "unsupported url",
    "is not a valid url",
    "does not exist",
)
_LOGIN_KEYS = ("sign in", "cookies", "login required")
_NETWORK_KEYS = ("unable to download", "timed out", "connection", "getaddrinfo", "http error 5")


def map_ytdlp_error(exc: BaseException, *, searching: bool = False) -> AppError:
    message = str(exc).lower()
    logger.warning("yt-dlp falhou: %s", exc)
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
        return AppError(
            "youtube_unavailable", "Não deu para falar com o YouTube agora. Tente de novo.", 502
        )
    return AppError("download_failed", "Não foi possível baixar o áudio deste vídeo.", 502)


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


def _caused_by(exc: BaseException, kind: type[BaseException]) -> bool:
    """O yt-dlp embrulha a exceção do hook num `DownloadError` (em `exc_info`)."""
    pending: list[BaseException] = [exc]
    seen: set[int] = set()
    while pending:
        current = pending.pop()
        if id(current) in seen:
            continue
        seen.add(id(current))
        if isinstance(current, kind):
            return True
        exc_info = getattr(current, "exc_info", None)
        if (
            isinstance(exc_info, tuple)
            and len(exc_info) > 1
            and isinstance(exc_info[1], BaseException)
        ):
            pending.append(exc_info[1])
        pending += [e for e in (current.__cause__, current.__context__) if e is not None]
    return False
