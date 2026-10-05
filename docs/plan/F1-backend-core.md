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
_Preencher ao final da sessão._
