from pathlib import Path
from typing import Any

import pytest
from yt_dlp.utils import DownloadError

from app.domain.errors import AppError
from app.domain.text import guess_identity
from app.pipeline.download import (
    YtDlpClient,
    find_downloaded,
    map_ytdlp_error,
    to_search_result,
)
from app.pipeline.queue import JobCancelledError


class FakeYdl:
    """Dublê do `YoutubeDL`: guarda as opções e devolve/levanta o que o teste mandar."""

    def __init__(self, options: dict[str, Any], *, result: Any = None, error: Any = None) -> None:
        self.options = options
        self.result = result
        self.error = error
        self.calls: list[tuple[str, bool]] = []
        self.on_download: Any = None

    def __enter__(self) -> "FakeYdl":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def extract_info(self, target: str, download: bool) -> Any:
        self.calls.append((target, download))
        if self.on_download is not None:
            self.on_download(self)
        if self.error is not None:
            raise self.error
        return self.result


def make_client(
    *, result: Any = None, error: Any = None, on_download: Any = None, **kwargs: Any
) -> tuple[YtDlpClient, list[FakeYdl]]:
    made: list[FakeYdl] = []

    def factory(options: dict[str, Any]) -> FakeYdl:
        ydl = FakeYdl(options, result=result, error=error)
        ydl.on_download = on_download
        made.append(ydl)
        return ydl

    defaults: dict[str, Any] = {"js_runtimes": ["deno", "node"], "cookie_file": None, "timeout": 60}
    defaults.update(kwargs)
    return YtDlpClient(ydl_factory=factory, **defaults), made


class FakeProgress:
    def __init__(self) -> None:
        self.cancelled = False
        self.values: list[float] = []

    def progress(self, percent: float) -> None:
        self.values.append(percent)


ENTRY = {
    "id": "abc123",
    "title": "Queen - Bohemian Rhapsody (Official Video Remastered)",
    "channel": "Queen Official",
    "duration": 359.0,
    "url": "https://www.youtube.com/watch?v=abc123",
    "thumbnails": [{"url": "https://i.ytimg.com/a.jpg"}, {"url": "https://i.ytimg.com/b.jpg"}],
}


# --- busca -------------------------------------------------------------------


def test_busca_por_texto_usa_ytsearch_e_monta_resultados() -> None:
    client, made = make_client(result={"entries": [ENTRY, {"title": ""}, None]})

    results = client.search("  queen bohemian  ")

    assert made[0].calls == [("ytsearch10:queen bohemian", False)]
    assert made[0].options["extract_flat"] == "in_playlist"
    assert made[0].options["js_runtimes"] == {"deno": {}, "node": {}}
    assert len(results) == 1
    result = results[0]
    assert result.source_url == "https://www.youtube.com/watch?v=abc123"
    assert result.source_channel == "Queen Official"
    assert result.duration_s == 359.0
    assert result.thumbnail_url == "https://i.ytimg.com/b.jpg"
    assert (result.artist, result.title) == ("Queen", "Bohemian Rhapsody")


def test_busca_por_url_extrai_o_proprio_video() -> None:
    client, made = make_client(result={**ENTRY, "webpage_url": ENTRY["url"]})

    results = client.search("https://youtu.be/abc123")

    assert made[0].calls == [("https://youtu.be/abc123", False)]
    assert [r.source_url for r in results] == ["https://www.youtube.com/watch?v=abc123"]


def test_busca_sem_resultados_nao_e_erro() -> None:
    client, _ = make_client(result={"entries": []})

    assert client.search("xyzxyz") == []


def test_youtube_fora_do_ar_e_erro_e_nao_lista_vazia() -> None:
    client, _ = make_client(error=DownloadError("Unable to download API page: timed out"))

    with pytest.raises(AppError) as exc:
        client.search("queen")

    assert exc.value.code == "youtube_unavailable"
    assert exc.value.status == 502


def test_cookie_file_vai_para_as_opcoes(tmp_path: Path) -> None:
    cookies = tmp_path / "cookies.txt"
    client, made = make_client(result={"entries": []}, cookie_file=cookies)

    client.search("queen")

    assert made[0].options["cookiefile"] == str(cookies)


# --- identidade --------------------------------------------------------------


@pytest.mark.parametrize(
    ("source_title", "channel", "expected"),
    [
        (
            "Queen - Bohemian Rhapsody (Official Video)",
            "Queen Official",
            ("Queen", "Bohemian Rhapsody"),
        ),
        ("Legião Urbana – Tempo Perdido [Clipe Oficial]", None, ("Legião Urbana", "Tempo Perdido")),
        ("Bohemian Rhapsody (Remastered 2011)", "Queen - Topic", ("Queen", "Bohemian Rhapsody")),
        ("Hello", "AdeleVEVO", ("Adele", "Hello")),
        ("Song (Live at Wembley)", "Band", ("Band", "Song (Live at Wembley)")),
        (
            "The Beatles - The Beatles - Let It Be (Official Music Video) [Remastered 2015]",
            "The Beatles",
            ("The Beatles", "Let It Be"),
        ),
    ],
)
def test_guess_identity(source_title: str, channel: str | None, expected: tuple[str, str]) -> None:
    assert guess_identity(source_title, channel) == expected


def test_resultado_sem_titulo_ou_url_e_ignorado() -> None:
    assert to_search_result({"title": "x"}) is None
    assert to_search_result({"id": "abc", "title": ""}) is None
    assert to_search_result({"id": "abc", "title": "x"}) is not None


# --- download ----------------------------------------------------------------


def test_download_salva_source_e_reporta_progresso(tmp_path: Path) -> None:
    def fake_download(ydl: FakeYdl) -> None:
        hook = ydl.options["progress_hooks"][0]
        hook({"status": "downloading", "downloaded_bytes": 50, "total_bytes": 100})
        (tmp_path / "source.webm").write_bytes(b"audio")

    client, made = make_client(result={}, on_download=fake_download)
    ctx = FakeProgress()

    path = client.download("https://youtu.be/abc", tmp_path, ctx)

    assert path == tmp_path / "source.webm"
    assert made[0].options["format"] == "bestaudio/best"
    assert made[0].options["outtmpl"] == str(tmp_path / "source.%(ext)s")
    assert ctx.values == [50.0, 100]


def test_download_cancelado_pelo_hook(tmp_path: Path) -> None:
    def fake_download(ydl: FakeYdl) -> None:
        try:
            ydl.options["progress_hooks"][0]({"status": "downloading"})
        except Exception as exc:
            # O yt-dlp embrulha a exceção do hook.
            raise DownloadError("interrompido", exc_info=(type(exc), exc, None)) from None

    client, _ = make_client(on_download=fake_download)
    ctx = FakeProgress()
    ctx.cancelled = True

    with pytest.raises(JobCancelledError):
        client.download("https://youtu.be/abc", tmp_path, ctx)


def test_download_timeout(tmp_path: Path) -> None:
    def fake_download(ydl: FakeYdl) -> None:
        ydl.options["progress_hooks"][0]({"status": "downloading"})

    client, _ = make_client(on_download=fake_download, timeout=-1)

    with pytest.raises(AppError) as exc:
        client.download("https://youtu.be/abc", tmp_path, FakeProgress())

    assert exc.value.code == "download_timeout"


def test_download_sem_arquivo(tmp_path: Path) -> None:
    client, _ = make_client(result={})

    with pytest.raises(AppError) as exc:
        client.download("https://youtu.be/abc", tmp_path, FakeProgress())

    assert exc.value.code == "download_failed"


@pytest.mark.parametrize(
    ("message", "code"),
    [
        (
            "Sign in to confirm you're not a bot. Use --cookies-from-browser",
            "youtube_login_required",
        ),
        ("Sign in to confirm your age. This video may be inappropriate", "age_restricted"),
        ("Private video. Sign in if you've been granted access", "video_unavailable"),
        ("Unable to download API page: HTTP Error 503", "youtube_unavailable"),
        ("Video unavailable. This video has been removed by the uploader", "video_unavailable"),
        ("Unsupported URL: https://example.com", "video_unavailable"),
        (
            "Unable to download webpage: <urlopen error [Errno 11001] getaddrinfo failed>",
            "youtube_unavailable",
        ),
        ("Requested format is not available", "video_unavailable"),
        ("algo estranho", "download_failed"),
    ],
)
def test_mapeamento_de_erros(message: str, code: str) -> None:
    error = map_ytdlp_error(DownloadError(f"ERROR: {message}"))

    assert error.code == code
    assert error.message


def test_mensagem_de_login() -> None:
    error = map_ytdlp_error(DownloadError("ERROR: Sign in to confirm you're not a bot"))

    assert error.message == "YouTube pediu login. Atualize os cookies."


def test_find_downloaded_ignora_partes(tmp_path: Path) -> None:
    (tmp_path / "source.webm.part").write_bytes(b"x")
    assert find_downloaded(tmp_path) is None
    (tmp_path / "source.webm").write_bytes(b"x")
    (tmp_path / "source.m4a").write_bytes(b"x")

    assert find_downloaded(tmp_path) == tmp_path / "source.m4a"
