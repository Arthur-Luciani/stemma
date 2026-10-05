import textwrap
import threading
from pathlib import Path
from typing import Any

import pytest
from yt_dlp.utils import DownloadError

from app.domain.errors import AppError
from app.domain.text import guess_identity
from app.pipeline.download import (
    YtDlpClient,
    error_lines,
    find_downloaded,
    map_ytdlp_error,
    to_search_result,
)
from app.pipeline.queue import CancellableTask, JobCancelledError


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


# `python -m yt_dlp` falso: comportamento pelo env FAKE_YTDLP (ok|login|sleep|empty).
FAKE_YTDLP = textwrap.dedent(
    """
    import os, sys, time
    from pathlib import Path

    args = sys.argv[1:]
    Path(os.environ["FAKE_YTDLP_LOG"]).write_text("\\n".join(args))
    mode = os.environ.get("FAKE_YTDLP", "ok")
    if mode == "login":
        print("ERROR: [youtube] abc: Sign in to confirm you're not a bot.", file=sys.stderr)
        sys.exit(1)
    if mode == "sleep":
        time.sleep(30)
    print("[stemma] 500/1000/NA", flush=True)
    time.sleep(0.3)
    if mode != "empty":
        out = args[args.index("--output") + 1].replace("%(ext)s", "webm")
        Path(out).write_bytes(b"audio")
    print("[stemma] 1000/1000/NA", flush=True)
    """
)


@pytest.fixture
def fake_ytdlp(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    package = tmp_path / "fakemods" / "yt_dlp"
    package.mkdir(parents=True)
    (package / "__init__.py").write_text("")
    (package / "__main__.py").write_text(FAKE_YTDLP)
    log = tmp_path / "ytdlp-args.txt"
    monkeypatch.setenv("PYTHONPATH", str(tmp_path / "fakemods"))
    monkeypatch.setenv("FAKE_YTDLP_LOG", str(log))
    return log


class FakeCtx(FakeProgress):
    def __init__(self) -> None:
        super().__init__()
        self.task: CancellableTask | None = None

    def attach(self, task: CancellableTask | None) -> None:
        self.task = task


def test_comando_de_download(tmp_path: Path) -> None:
    client, _ = make_client(js_runtimes=["node"], cookie_file=tmp_path / "c.txt")

    cmd = client.download_command("https://youtu.be/abc", tmp_path)

    assert cmd[1:3] == ["-m", "yt_dlp"]
    assert cmd[cmd.index("--format") + 1] == "bestaudio/best"
    assert cmd[cmd.index("--output") + 1] == str(tmp_path / "source.%(ext)s")
    assert cmd.index("--no-js-runtimes") < cmd.index("--js-runtimes")
    assert cmd[cmd.index("--js-runtimes") + 1] == "node"
    assert cmd[cmd.index("--cookies") + 1] == str(tmp_path / "c.txt")
    assert cmd[-2:] == ["--", "https://youtu.be/abc"]


def test_download_salva_source_e_reporta_progresso(tmp_path: Path, fake_ytdlp: Path) -> None:
    client, _ = make_client()
    ctx = FakeCtx()

    path = client.download("https://youtu.be/abc", tmp_path / "raw", ctx)

    assert path == tmp_path / "raw" / "source.webm"
    assert 50.0 in ctx.values
    assert ctx.values[-1] == 100
    assert "https://youtu.be/abc" in fake_ytdlp.read_text()


def test_download_com_erro_de_login(
    tmp_path: Path, fake_ytdlp: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("FAKE_YTDLP", "login")
    client, _ = make_client()

    with pytest.raises(AppError) as exc:
        client.download("https://youtu.be/abc", tmp_path, FakeCtx())

    assert exc.value.code == "youtube_login_required"


def test_download_cancelado_mata_o_processo(
    tmp_path: Path, fake_ytdlp: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("FAKE_YTDLP", "sleep")
    client, _ = make_client()
    ctx = FakeCtx()

    def cancel() -> None:
        ctx.cancelled = True
        if ctx.task is not None:
            ctx.task.cancel()

    timer = threading.Timer(1.0, cancel)
    timer.start()
    try:
        with pytest.raises(JobCancelledError):
            client.download("https://youtu.be/abc", tmp_path, ctx)
    finally:
        timer.cancel()


def test_download_timeout(
    tmp_path: Path, fake_ytdlp: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # Trava antes do primeiro byte: o timeout total ainda vale.
    monkeypatch.setenv("FAKE_YTDLP", "sleep")
    client, _ = make_client(timeout=1)

    with pytest.raises(AppError) as exc:
        client.download("https://youtu.be/abc", tmp_path, FakeCtx())

    assert exc.value.code == "download_timeout"


def test_download_sem_arquivo(
    tmp_path: Path, fake_ytdlp: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("FAKE_YTDLP", "empty")
    client, _ = make_client()

    with pytest.raises(AppError) as exc:
        client.download("https://youtu.be/abc", tmp_path, FakeCtx())

    assert exc.value.code == "download_failed"


def test_busca_com_timeout_total() -> None:
    hold = threading.Event()
    client, _ = make_client(on_download=lambda _ydl: hold.wait(5), search_timeout=0.2)
    try:
        with pytest.raises(AppError) as exc:
            client.search("queen")
    finally:
        hold.set()

    assert exc.value.code == "youtube_unavailable"


def test_erro_do_subprocess_usa_so_as_linhas_de_erro() -> None:
    output = "[youtube] abc: Downloading webpage\nERROR: [youtube] abc: Private video"

    assert error_lines(output) == "ERROR: [youtube] abc: Private video"
    assert error_lines("sem erro marcado") == "sem erro marcado"


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
        ("Requested format is not available. Use --list-formats", "youtube_format_unavailable"),
        ("Service is unavailable", "download_failed"),
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
