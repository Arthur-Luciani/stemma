# F0 — Fundação

## Objetivo
Repo pronto para desenvolver: estrutura, tooling, CI e release automatizado funcionando de ponta a ponta, sem nenhuma funcionalidade de produto ainda.

## Escopo
- `.gitignore` completo (venv/.venv, `__pycache__`, `.pytest_cache`, `node_modules`, `dist`, `*.db*`, `*.bak`, `.env`, `storage/`, `.claude/`, logs).
- `.editorconfig`, `.gitattributes` (LF), `.env.example` com **todas** as variáveis previstas (comentadas).
- **Backend** (`backend/`): `pyproject.toml` com grupos `api`/`pipeline`/`dev`, `uv.lock`, Python fixado ([ADR 0008](../decisions/0008-python-e-deps.md)); esqueleto `app/` conforme CLAUDE.md com `create_app()`, `config.py` (pydantic-settings, lê `.env`) e `GET /health` → `{status, version}`; ruff (lint + format) e mypy (strict em `app/`); pytest com 1 teste do `/health`.
- **Validar ambiente de GPU**: num venv local com o grupo `pipeline`, confirmar que torch cu118 enxerga a GPU e que `python -m demucs --help` roda na versão de Python escolhida. Registrar resultado na ADR 0008 (status → aceita).
- **Frontend** (`frontend/`): Vite + React 18 + TypeScript strict; ESLint (typescript-eslint, react-hooks com `exhaustive-deps` = error), Prettier, Vitest + Testing Library; tokens de `docs/design/README.md` em `src/styles/tokens.css`; fontes via `<link>`; `index.html` com `lang="pt-BR"`, viewport com `viewport-fit=cover`, `theme-color`; uma página placeholder com o wordmark `stemma` usando os tokens; 1 teste.
- Scripts npm: `dev`, `build`, `lint`, `typecheck`, `test`, `format`.
- **CI** `.github/workflows/ci.yml`: jobs `backend` e `frontend` em `ubuntu-latest`, com cache (uv e npm), conforme [ADR 0007](../decisions/0007-processo-de-release.md). Job `pr-title` com `amannn/action-semantic-pull-request`.
- **Release** `.github/workflows/release.yml` + `release-please-config.json` + `.release-please-manifest.json` (versão inicial 0.0.0 → primeira release 0.1.0), atualizando `backend/pyproject.toml` e `frontend/package.json`. Job pós-release que builda o frontend e anexa `stemma-vX.Y.Z.zip` + `.sha256`.
- `scripts/dev.ps1`: sobe backend (`uvicorn --reload`, porta 8010) e frontend (Vite, porta 5183, proxy `/api` `/ws` `/health`, `allowedHosts: [".ts.net"]`) — portas diferentes da v1 para coexistirem.
- Preencher a seção **Comandos** do `CLAUDE.md` com os comandos reais.
- `README.md` curto (o que é, como rodar em dev, link para `docs/`).

## Fora do escopo
Banco, rotas de produto, UI real, WinSW/serviço (F5).

## Checklist
- [ ] `.gitignore`, `.editorconfig`, `.gitattributes`, `.env.example`
- [ ] backend: pyproject + uv.lock + esqueleto + `/health` + ruff/mypy/pytest verdes
- [ ] GPU validada localmente; ADR 0008 atualizada
- [ ] frontend: Vite/React/TS + ESLint/Prettier/Vitest + tokens + placeholder + teste
- [ ] `ci.yml` verde num PR
- [ ] release-please configurado; merge gera PR de release; merge do PR de release gera `v0.1.0` com zip anexado
- [ ] `scripts/dev.ps1` funcionando (abrir no celular via Tailscale mostra o placeholder)
- [ ] CLAUDE.md (Comandos) e README atualizados

## Critério de pronto
Um PR com CI verde é mergeado e a GitHub Release **v0.1.0** existe com `stemma-v0.1.0.zip` + SHA256 anexados.

## Ação manual do usuário ao final
Ativar branch protection em `main` exigindo os checks `backend`, `frontend` e `pr-title`.

## Handoff
_Preencher ao final da sessão: feito, pendente, decisões, pegadinhas, pendências descobertas._
