"""Configuração da aplicação, lida de variáveis de ambiente e do `.env`."""

from functools import lru_cache
from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

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

    @field_validator("storage_root")
    @classmethod
    def _resolve_storage_root(cls, value: Path) -> Path:
        # Relativo à raiz do repo, não ao diretório de trabalho do processo.
        return value if value.is_absolute() else (REPO_DIR / value).resolve()


@lru_cache
def get_settings() -> Settings:
    return Settings()
