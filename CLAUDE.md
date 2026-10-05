# CLAUDE.md

Guia para o Claude Code (e humanos) trabalhando neste repositório. Leia inteiro no início de cada sessão.

## O que é

**Stemma**: app pessoal, single-user, que baixa uma música (busca ou link do YouTube via yt-dlp), separa em 4 stems com Demucs (voz, bateria, baixo, outros) e oferece um mixer por stem (volume, pan, mute, solo, loop A–B, presets) e export do mixdown. Roda como serviço no PC Windows com GPU NVIDIA e é usado no desktop e no celular via Tailscale (HTTPS + PWA).

É a reescrita do `music-analyzer` (v1, repo `Arthur-Luciani/music-analyzer`, local em `C:\git\music-analyzer`). A v1 é **referência de lógica que funciona**, não de estrutura — ver `docs/reference-v1.md`. O inspetor de bateria e o catálogo MIDI da v1 **não** existem aqui.

## Onde está cada coisa

| O quê | Onde |
|---|---|
| Plano e status das fases | `docs/plan/README.md` (comece por aqui) |
| Fase atual: escopo, checklist, critério de pronto, handoff | `docs/plan/F*.md` |
| Decisões de arquitetura (e o porquê) | `docs/decisions/` (ADRs) |
| Design: tokens, componentes, telas | `docs/design/README.md` |
| **Projeto de design (fonte da verdade visual)** | Claude Design: https://claude.ai/design/p/e8a6b561-5c39-487b-8fb1-c0ff17dfed7b — arquivos `Stemma - Marca e Sistema`, `Stemma - Celular`, `Stemma - Desktop` |
| Lógica da v1 a portar | `docs/reference-v1.md` |
| Prompt padrão das sessões | `docs/SESSION_PROMPT.md` |

## Arquitetura (alvo)

```
backend/   FastAPI + SQLAlchemy 2 + Alembic (SQLite) — Python 3.12, deps via uv
  app/api/        routers finos (sem lógica de negócio), deps.py com Depends
  app/services/   regras de negócio (sessions, identity, mix, exports, events)
  app/pipeline/   JobRunner (fila persistente) + download/separate/audio (subprocess)
  app/db/         models ORM, engine/sessão
  app/schemas/    Pydantic da API (separado do ORM)
  app/domain/     enums, erros de domínio, regras puras
frontend/  React + TypeScript + Vite
  src/api/        ÚNICO lugar com fetch/WebSocket; tipos gerados do OpenAPI
  src/features/   discover, library, session, mixer (hooks + componentes da feature)
  src/ui/         componentes base do design system
  src/audio/      AudioEngine (fora do React)
deploy/    WinSW XML, start.ps1, update.ps1
```

Um processo uvicorn (1 worker) serve `/api`, `/ws` e o `frontend/dist` na mesma origem, atrás de `tailscale serve`.

## Regras (não negociáveis)

**Backend**
- Rotas só validam entrada, chamam um service e serializam a saída. Nada de SQL ou regra de negócio em `api/`.
- Services não chamam outros services por atalhos privados; dependências entram por construtor/`Depends`.
- **O banco é a fonte da verdade.** Nada de cache de estado de job em memória; o EventBus só propaga eventos.
- Trabalho pesado (yt-dlp, Demucs, ffmpeg) só dentro de `pipeline/`, sempre via subprocess com timeout, stderr capturado e binário vindo de `config`.
- Paths no banco são **relativos** ao `STORAGE_ROOT`; resolva com o helper único que também valida contenção.
- Erros: levante `AppError(code, message, status)`; a API responde sempre `{"error": {"code", "message"}}`. Mensagens ao usuário em PT-BR.
- Datas com timezone (`datetime.now(UTC)`). Logging via `logging`, nunca `print`.
- Toda mudança de schema = migration Alembic. Testes de persistência sobem o banco via `alembic upgrade head`, não `create_all`.
- Constantes de domínio (stems, estados) definidas **uma vez** em `domain/`.

**Frontend**
- `fetch`/`WebSocket` só em `src/api/`. Server state via TanStack Query; nada de duplicar sessão em contexts.
- Toda tela tem URL (React Router). O back do Android tem que funcionar.
- Estilo só com tokens (`var(--…)`) e CSS Modules. Sem hex solto, sem `style={{}}` exceto valores dinâmicos (ex.: posição do playhead).
- Áudio só pelo `AudioEngine`; React não roda nada a 60 fps. `AudioContext` sempre fechado no unmount.
- Mobile-first; alvos de toque ≥ 44px; nada depende de hover.
- UI em português do Brasil com acentuação correta; sem CAIXA ALTA em botões.

**Processo**
- Uma branch por tarefa, PR com squash merge, título em Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).
- CI verde é obrigatório. Não desabilite regra de lint para passar; corrija.
- Antes de mudanças transversais (que tocam muitos arquivos), **liste tudo o que será afetado e só depois implemente** num passo consistente.
- Ao terminar uma fase, atualize o checklist e a seção **Handoff** do arquivo da fase e a tabela de status em `docs/plan/README.md`.
- Decisão de arquitetura nova ou mudada → ADR em `docs/decisions/`.

## Comandos

```bash
# tudo junto (Windows): backend :8010 (--reload) + Vite :5183 com proxy de /api, /ws e /health
powershell -ExecutionPolicy Bypass -File scripts/dev.ps1   # -SkipInstall pula uv sync/npm ci

# backend (Python 3.12 fixado em backend/.python-version; o uv instala se faltar)
cd backend
uv sync --group api --group dev          # o que o CI usa
uv sync --all-groups                     # + torch cu118/demucs (só no PC com GPU)
uv run pytest
uv run ruff check . && uv run ruff format --check . && uv run mypy app
uv run alembic upgrade head             # cria/atualiza o banco (o dev.ps1 já roda)
uv run alembic revision --autogenerate -m "descrição"   # após mudar app/db/models.py
uv run uvicorn app.main:app --reload --port 8010
uv run python -m app.cli cleanup --dry-run   # órfãos no STORAGE_ROOT parados há 60+ min (sem --dry-run apaga)

# frontend (Node >= 22.12)
cd frontend && npm ci
npm run dev          # http://127.0.0.1:5183
npm run lint && npm run format:check && npm run typecheck && npm test && npm run build
npm run format       # aplica Prettier
npm run gen:api      # regenera src/api/openapi.json + schema.d.ts (após mudar rotas/schemas; precisa do uv)
```

Cuidados:
- `uv sync` sem `--inexact` **remove** o grupo `pipeline` se ele estiver instalado; para manter torch/demucs use `uv sync --all-groups` ou `--inexact`.
- Mudou rota ou schema da API → `npm run gen:api` e commite os dois arquivos gerados; o CI acusa drift.
- Versão do app: `backend/pyproject.toml` e `frontend/package.json` são atualizados **só** pelo release-please (PR de release). Não edite à mão.

## Ambiente

- Windows 11, GPU NVIDIA (CUDA, torch cu118), FFmpeg via winget.
- Dados fora do repo: `STORAGE_ROOT` (padrão de produção `D:\stemma-data`).
- CI (GitHub Actions, runners Linux gratuitos) **nunca** instala o grupo `pipeline` (torch/demucs).
