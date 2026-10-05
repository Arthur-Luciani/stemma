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
- [x] `.gitignore`, `.editorconfig`, `.gitattributes`, `.env.example`
- [x] backend: pyproject + uv.lock + esqueleto + `/health` + ruff/mypy/pytest verdes
- [x] GPU validada localmente; ADR 0008 atualizada
- [x] frontend: Vite/React/TS + ESLint/Prettier/Vitest + tokens + placeholder + teste
- [x] `ci.yml` verde num PR (#2)
- [x] release-please configurado; merge gera PR de release; merge do PR de release gera release com zip anexado — saiu **`v1.0.0`**, não `v0.1.0` (ver Handoff)
- [ ] `scripts/dev.ps1` funcionando (abrir no celular via Tailscale mostra o placeholder) — local OK (página + proxy `/health`); **teste no celular adiado** (ver Handoff)
- [x] CLAUDE.md (Comandos) e README atualizados

## Critério de pronto
Um PR com CI verde é mergeado e a GitHub Release **v0.1.0** existe com `stemma-v0.1.0.zip` + SHA256 anexados.

## Ação manual do usuário ao final
Ativar branch protection em `main` exigindo os checks `backend`, `frontend` e `pr-title`.

## Handoff

**Status:** concluída em 2026-10-05. PRs #2 (`feat: fundação do projeto (F0)`) e #3 (release) mergeados, CI verde. Release [v1.0.0](https://github.com/Arthur-Luciani/stemma/releases/tag/v1.0.0) com `stemma-v1.0.0.zip` + `.sha256` (hash conferido com `sha256sum -c`).

### Feito
- Raiz: `.gitignore`, `.editorconfig`, `.gitattributes`, `.env.example` (todas as variáveis previstas, marcadas com a fase em que passam a valer).
- Backend: `pyproject.toml` (grupos `api`/`pipeline`/`dev`), `uv.lock`, Python 3.12, `create_app()`, `config.py` (`Settings` + `get_settings()`), `GET /health` → `{status, version}` (versão via `importlib.metadata`), pastas `api/ services/ pipeline/ db/ schemas/ domain/`. ruff, mypy strict, pytest (3 testes: health + resolução do `STORAGE_ROOT`).
- GPU validada: torch 2.7.1+cu118 na GTX 1650, Demucs 4.0.1 separando em `cuda`. [ADR 0008](../decisions/0008-python-e-deps.md) aceita.
- Frontend: Vite 8, React 18, TypeScript 6.0 strict, ESLint 10 (type-checked + `exhaustive-deps` = error), Prettier, Vitest 5 + Testing Library; `src/styles/tokens.css` com todos os tokens do design; placeholder com ícone e wordmark; favicon SVG.
- CI (`backend`, `frontend`, `pr-title`) e release (`release-please` + job `package` no mesmo workflow).
- `scripts/dev.ps1`, CLAUDE.md (Comandos) e README.

### Pendente
- **Teste no celular via Tailscale** (adiado pelo usuário): `scripts/dev.ps1` + `tailscale serve --bg --https=5183 http://127.0.0.1:5183`, abrir `https://<máquina>.<tailnet>.ts.net:5183`. Fazer até a F3 no máximo.
- **Branch protection** na `main` exigindo `backend`, `frontend` e `pr-title` (ação do usuário). Ler a pegadinha do release-please abaixo antes.

### Decisões
- **Primeira release saiu v1.0.0** (não v0.1.0): o release-please ignora o `0.0.0` do manifest na primeira release e usa `1.0.0` como versão inicial; faltou `"initial-version": "0.1.0"`. Usuário optou por manter. Daqui em diante SemVer normal a partir de 1.0.0 (`feat` → minor, `fix` → patch).
- Python 3.12 + torch/torchaudio 2.7.1 cu118 (última série com cu118); lock restrito a Windows/Linux.
- `httpx2` no lugar de `httpx` (o Starlette atual depreca `httpx` no `TestClient`).
- TypeScript fixado em `~6.0`: o typescript-eslint 8 aceita `<6.1`.
- Vite escuta em `127.0.0.1` (não `host: true`): no Windows `localhost` resolvia só para `::1` e o `tailscale serve` aponta para 127.0.0.1.
- `STORAGE_ROOT` relativo é resolvido a partir da **raiz do repo**, não do diretório de trabalho (achado do `/code-review`).
- `.ps1` versionados em **CRLF + BOM** (`.gitattributes`/`.editorconfig`): o Windows PowerShell 5.1 lê UTF-8 sem BOM como ANSI e estraga acentos.
- release-please com `release-type: simple` (gera `CHANGELOG.md`) e `extra-files` para `backend/pyproject.toml`, `backend/uv.lock`, `frontend/package.json` e `frontend/package-lock.json`.

### Pegadinhas
- `uv sync` sem `--inexact` **desinstala** o grupo `pipeline` (torch). O `dev.ps1` usa `--inexact`; no PC use `uv sync --all-groups`.
- PRs/tags criados pelo release-please com `GITHUB_TOKEN` **não disparam outros workflows**: o PR de release não roda CI por si (no #3 o CI rodou disparado por ação manual do usuário — `triggering_actor` do run), e por isso o empacotamento fica no próprio `release.yml`. Com branch protection exigindo checks, o PR de release vai travar → passar um PAT/GitHub App no `token:` do release-please, ou não exigir checks para ele.
- Na abertura do PR #2 o CI não disparou; um commit vazio resolveu. Se acontecer de novo, `git commit --allow-empty` + push.
- `noUncheckedIndexedAccess` tipa classes de CSS Module como `string | undefined`; não use template string com elas (`restrict-template-expressions`) — prefira `composes` no CSS ou um helper `cx` quando a F3 criar `ui/`.
- Arquivos Markdown escritos por scripts Python no Windows saem em CRLF se não passar `newline` explícito; confira com `git diff` antes de commitar.

### Pendências descobertas
- Nenhuma fora do escopo das próximas fases. Alembic e drift de tipos OpenAPI entram no CI na F1, como previsto na [ADR 0007](../decisions/0007-processo-de-release.md).
