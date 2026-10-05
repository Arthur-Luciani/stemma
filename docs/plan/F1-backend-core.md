# F1 — Backend core

## Objetivo
Base do backend: banco, modelo de dados, sessões e identidade com API estável e testada. Sem pipeline ainda.

## Escopo
- `db/`: engine SQLite com WAL, `busy_timeout`, `foreign_keys=ON`; sessão por request via `Depends`.
- Modelo (SQLAlchemy 2, `Mapped[]`, colunas JSON nativas), **migration baseline única**:
  - `sessions`: id (UUID), `code` (`ST-###`, sequência no ORM), `source_url`, `source_title`, `source_channel`, `thumbnail_url`, `artist`, `title`, `duration_s`, `state` (draft/queued/downloading/separating/ready/failed), `progress`, `error_code`, `error_message`, `stems` (JSON com paths **relativos**), `metrics` (JSON: lufs, true_peak), `created_at`, `updated_at`, `processed_at`.
  - `jobs` (estrutura da fila; uso na F2a), `session_events` (log append-only), `mix_states` (por sessão: volume/pan/mute/solo por stem, preset, loop A–B), `exports` (formato wav/mp3, preset/níveis usados, state, progress, path relativo, tamanho, lufs).
- `domain/`: enums `SessionState`, `JobKind`, `JobState`, `ExportFormat`, `Stem` (vocals/drums/bass/other com rótulos PT-BR Voz/Bateria/Baixo/Outros) — **definidos uma vez**.
- `AppError` + exception handler → `{"error": {"code", "message"}}`; validação de UUID nos path params; helper único de paths (`storage.resolve(rel)` com checagem de contenção).
- `services/sessions.py`: criar rascunho, listar (busca texto, filtro por estado, ordenação, paginação, **contagem por estado**), obter, editar artista/título, excluir (atômico, remove arquivos do disco, cascade).
- `services/identity.py`: autocomplete de artistas já usados com contagem de sessões (normalização portada da v1).
- `services/mix.py`: obter/salvar mix state.
- Rotas (`api/`): `GET/POST /api/sessions`, `GET/PATCH/DELETE /api/sessions/{id}`, `GET /api/artists?q=`, `GET/PUT /api/sessions/{id}/mix`.
- `GET /health` → `{status, version, db, ffmpeg, js_runtime, gpu}` (checagens baratas; gpu pode ser "unknown" até F2b).
- Logging configurado no startup (formato com timestamp, nível via env).
- **OpenAPI → tipos TS**: script `npm run gen:api` (no frontend) que gera `src/api/schema.d.ts` a partir do `/openapi.json`; tipos commitados; CI falha se houver drift.
- Testes: TestClient para todas as rotas; persistência com banco subido via `alembic upgrade head`; teste que a migration bate com os models (autogenerate vazio).

## Fora do escopo
Busca no YouTube, processamento, WebSocket, export real (F2a/F2b).

## Checklist
- [x] db + models + migration baseline + teste de drift de migration
- [x] domain (enums/erros) + handler de erro + validação de IDs + helper de paths
- [x] services sessions/identity/mix + rotas
- [x] `/health` completo + logging
- [x] geração de tipos OpenAPI + checagem de drift no CI
- [x] testes de API cobrindo sucesso e erros principais

## Critério de pronto
CRUD de sessões, identidade e mix state testados via TestClient; CI verde; tipos TS gerados e commitados.

## Handoff
**Status:** concluída em 2026-10-05. PR #5 (`feat: backend core (F1)`) com CI verde (`backend`, `frontend`, `pr-title`), aguardando o merge.

### Feito
- `app/db/`:
  - `engine.py`: WAL, `busy_timeout=5000`, `foreign_keys` e a collation `pt_nocase`;
  - `models.py`: `sessions`, `counters`, `jobs`, `session_events`, `mix_states`, `exports`, todos com FK `ON DELETE CASCADE`;
  - `types.py` (`UTCDateTime`) e `deps.py` (sessão por request).
- Alembic: `backend/alembic.ini` + `backend/migrations/`, com a baseline `0001` (que semeia o contador `session_code`).
- `app/domain/`: `enums.py`, `errors.py` (`AppError` e subclasses) e `text.py` (normalização da v1).
- `app/storage.py`: `Storage.resolve(rel)` / `relative(path)` / `session_dir(id)`, com checagem de contenção.
- Services e rotas:
  - `sessions`: criar rascunho, listar com busca/filtro/contagens/ordenação/paginação, obter, editar identidade, excluir;
  - `identity`: `GET /api/artists?q=`;
  - `mix`: `GET/PUT /api/sessions/{id}/mix`;
  - `health`.
- Erros sempre em `{"error": {"code", "message"}}`, inclusive 422 (mensagens do Pydantic traduzidas em `api/errors.py`), 404 de rota e 500.
- Logging via `logging_setup.configure_logging` (timestamp, nível do `LOG_LEVEL`; o uvicorn usa o mesmo formato).
- OpenAPI → TS:
  - `python -m app.openapi` gera `frontend/src/api/openapi.json`, e o `openapi-typescript` gera `src/api/schema.d.ts`; `npm run gen:api` faz os dois;
  - o CI acusa drift nos dois jobs ([ADR 0007](../decisions/0007-processo-de-release.md), atualização F1).
- CI: smoke `alembic upgrade head`. O `dev.ps1` roda `alembic upgrade head` antes do uvicorn.
- 97 testes (pytest), cobrindo:
  - rotas com sucesso e erros;
  - drift de migration (autogenerate vazio) e PRAGMAs;
  - storage e normalização;
  - regressões do code review.

### Contrato da API (para F2a/F3)
- `SessionOut.stems` é a lista de stems **disponíveis** (sem paths); os arquivos serão servidos por rota da F2b.
- `GET /api/sessions` aceita `q`, `state` (repetível: `?state=queued&state=separating`), `sort` (`newest|oldest|title|artist|longest|shortest`), `limit` (1–100, padrão 30) e `offset`. Devolve `{items, total, counts}`, em que `counts` traz todos os estados e é calculado com a busca, mas sem o filtro de estado. O chip "Em andamento" da F3 é a soma de `queued + downloading + separating`.
- Mix: `{stems: {vocals|drums|bass|other: {volume 0–100, pan -1..1, mute, solo}}, preset, loop_a_s, loop_b_s, updated_at}`.
  - O PUT exige os 4 stems; o loop leva os dois pontos ou nenhum, com A < B e B ≤ duração.
  - O GET sem mix salvo devolve o padrão (Original, tudo em 100%, `updated_at: null`).
- `MixPreset` já tem `original, no_vocals, no_drums, no_bass, vocals_only, custom`; os níveis dos presets ficam no frontend (F4b).
- `DELETE` devolve 409 `session_busy` quando há job `queued`/`running` (a F2a deve manter isso).

### Pendente
- Merge do PR #5 (ação do usuário).
- Itens herdados da F0: teste no celular via Tailscale e branch protection.

### Decisões
- **Rotas só por UUID**; o `ST-###` é só para exibir. As URLs da F3 viraram `/sessions/:id` (o plano da F3 foi ajustado).
- **Duplicar removido** do produto, a pedido do usuário (F1, F3 e `docs/design/README.md`).
- **Volume de 0 a 100%** (sem ganho acima do original).
- Código `ST-###` vem da tabela `counters`, incrementada com `UPDATE … RETURNING`; **nunca reaproveita** o código de uma sessão excluída. Acima de 999 vira `ST-1000`.
- `sessions` ganhou `artist_key` (autocomplete agrupa "Queen Official" = "queen") e `search_key` (busca sem acento por código/artista/título/fonte), recalculados a cada escrita da identidade.
- Os services fazem **commit explícito**; o `get_db` só abre e fecha a sessão.
- `/health`:
  - `db` = `ok | outdated | error`, comparando `alembic_version` com o head das migrations;
  - `status` é `degraded` só por causa do banco;
  - binários ausentes aparecem como `missing`, mas não mudam o `status`.
- Drift do OpenAPI sem subir servidor; `info.version` fica fora do JSON para não gerar drift a cada release.
- `openapi-typescript` 7.13 declara peer `typescript ^5`; como usamos TS 6.0, foi resolvido com `overrides` no `package.json` (a geração funciona).
- `allowed-confusables = ["–"]` no ruff: o travessão é a grafia correta de "A–B" e "0–100".

### Pegadinhas
- **Migrations rodam com `foreign_keys=OFF`** (`make_engine(url, foreign_keys=False)` no `env.py`). O batch do SQLite recria tabelas com DROP, e com FKs ligadas isso apaga em cascade as tabelas filhas. Há um teste com controle que prova isso.
- Toda mudança em `app/db/models.py` precisa de `uv run alembic revision --autogenerate -m "..."`; o teste `test_migrations_batem_com_os_models` falha se faltar. Revise a migration gerada: o `UTCDateTime` sai como `sa.DateTime()` (via `render_item`), e é o esperado.
- No Windows, o `alembic.ini` não pode ter `timezone = UTC` (exige `tzdata`).
- Ordenação de texto usa a collation `pt_nocase`, registrada no connect do engine; uma query fora do engine do app (ex.: `sqlite3` na mão) não a conhece.
- `TestClient` relança exceções do servidor por padrão; para ver a resposta 500, use `TestClient(app, raise_server_exceptions=False)`.
- `dict[Enum, X]` no Pydantic vira `{[key: string]: X}` no TS (o `counts` e os `stems` do mix). Na F3, tipar com `Record<SessionState, number>` no client, se quiser.

### Pendências descobertas
- Nenhuma fora do escopo das próximas fases.
