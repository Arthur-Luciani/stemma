# 0008 — Python 3.12 e dependências com uv

- **Status:** aceita (2026-10-05, validada na F0)

## Contexto
A v1 rodava em Python 3.13 localmente e 3.10 no Docker; requirements sem lock, com o arquivo "leve" puxando torch indiretamente.

## Decisão
- `backend/pyproject.toml` com grupos: `api` (fastapi, uvicorn, sqlalchemy, alembic, pydantic-settings, yt-dlp), `pipeline` (torch cu118, torchaudio, demucs, soundfile), `dev` (pytest, httpx2, ruff, mypy). Lock com `uv.lock`.
- **Python 3.12** fixo (`backend/.python-version`, `requires-python = ">=3.12,<3.13"`). O 3.13 não foi testado: a 3.12 funcionou de primeira e não há ganho em mudar.
- torch/torchaudio vêm do índice explícito `pytorch-cu118` (`[tool.uv.sources]`) e estão fixados em **2.7.1**, a última série publicada para cu118.
- `[tool.uv] environments` restringe o lock a Windows e Linux (o PyTorch cu118 não tem wheels para macOS).

## Validação na F0 (PC de produção)
| Item | Resultado |
|---|---|
| GPU / driver | NVIDIA GeForce GTX 1650, driver 572.16 |
| Python | 3.12.9 (instalado pelo `uv python install 3.12`) |
| torch / torchaudio | 2.7.1+cu118 / 2.7.1+cu118, `torch.version.cuda` = 11.8, `cuda.is_available()` = True |
| demucs | 4.0.1; `python -m demucs --help` OK |
| Separação real | WAV sintético de 5 s com `htdemucs -d cuda` → 4 stems em ~14 s (incluindo carga do modelo) |

## Consequências
CI leve e determinístico; ambiente do PC reproduzível com `uv sync --all-groups`.
Subir o torch acima de 2.7.x exige trocar para cu126+ (o driver atual suporta CUDA 12.8); registrar numa ADR nova se acontecer.
