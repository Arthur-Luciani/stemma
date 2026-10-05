"""Configuração da aplicação, lida de variáveis de ambiente e do `.env`."""

from functools import lru_cache
from pathlib import Path
from typing import Annotated, Literal

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = BACKEND_DIR.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        # Arquivos posteriores têm precedência: backend/.env sobrescreve o da raiz.
        env_file=(REPO_DIR / ".env", BACKEND_DIR / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    host: str = "127.0.0.1"
    port: int = 8010
    log_level: str = "INFO"
    cors_origins: list[str] = []
    storage_root: Path = Path("storage")
    # Vazio = SQLite em <STORAGE_ROOT>/stemma.db.
    database_url: str = ""
    ffmpeg_bin: str = "ffmpeg"
    # Runtimes JS que o yt-dlp pode usar no YouTube, em ordem de preferência.
    ytdlp_js_runtime: Annotated[list[str], NoDecode] = ["deno", "node"]
    # Cookies exportados do navegador (formato Netscape), para quando o YouTube pede login.
    ytdlp_cookie_file: Path | None = None
    # Demucs (rodado como subprocess com o mesmo Python do app).
    separation_model: str = "htdemucs"
    # auto = tenta cuda e cai para cpu se a GPU falhar.
    demucs_device: Literal["auto", "cuda", "cpu"] = "auto"
    demucs_segment: int | None = Field(default=7, ge=1)
    demucs_overlap: float = Field(default=0.25, ge=0, lt=1)
    demucs_shifts: int = Field(default=1, ge=0)
    # Vazio = <STORAGE_ROOT>/cache/torch (onde o Demucs guarda os modelos baixados).
    torch_home: Path | None = None
    # Timeouts dos subprocessos, em segundos.
    download_timeout_s: float = Field(default=600, gt=0)
    separation_timeout_s: float = Field(default=1800, gt=0)
    ffmpeg_timeout_s: float = Field(default=300, gt=0)
    # Pipeline falso: simula download/separação sem yt-dlp/Demucs (desenvolvimento do frontend).
    stemma_fake_pipeline: bool = False
    fake_pipeline_seconds: float = Field(default=20.0, gt=0)
    # Tentativas de um job interrompido (servidor caiu no meio) antes de falhar.
    job_max_attempts: int = Field(default=2, ge=1)

    @field_validator("ytdlp_js_runtime", mode="before")
    @classmethod
    def _split_runtimes(cls, value: object) -> object:
        # No .env: `deno,node` (separado por vírgula).
        if isinstance(value, str):
            return [part.strip() for part in value.split(",") if part.strip()]
        return value

    @field_validator("ytdlp_cookie_file", "torch_home", mode="before")
    @classmethod
    def _empty_path(cls, value: object) -> object:
        return None if value == "" else value

    @field_validator("storage_root")
    @classmethod
    def _resolve_storage_root(cls, value: Path) -> Path:
        # Relativo à raiz do repo, não ao diretório de trabalho do processo.
        return value if value.is_absolute() else (REPO_DIR / value).resolve()

    @model_validator(mode="after")
    def _default_database_url(self) -> "Settings":
        if not self.database_url:
            self.database_url = f"sqlite:///{(self.storage_root / 'stemma.db').as_posix()}"
        if self.torch_home is None:
            self.torch_home = self.storage_root / "cache" / "torch"
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
