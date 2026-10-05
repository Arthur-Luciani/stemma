# 0008 — Python 3.12 e dependências com uv

- **Status:** proposta — confirmar na F0

## Contexto
A v1 rodava em Python 3.13 localmente e 3.10 no Docker; requirements sem lock, com o arquivo "leve" puxando torch indiretamente.

## Decisão
- `backend/pyproject.toml` com grupos: `api` (fastapi, uvicorn, sqlalchemy, alembic, pydantic-settings, yt-dlp), `pipeline` (torch cu118, torchaudio, demucs, soundfile), `dev` (pytest, httpx, ruff, mypy). Lock com `uv.lock`.
- **Python 3.12** fixo, a menos que a F0 confirme que torch cu118 + demucs funcionam bem em 3.13 nesta máquina; registrar o resultado aqui.

## Consequências
CI leve e determinístico; ambiente do PC reproduzível com `uv sync --all-groups`.
