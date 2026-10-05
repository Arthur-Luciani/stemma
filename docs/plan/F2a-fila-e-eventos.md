# F2a — Fila de jobs e eventos ao vivo

## Objetivo
Infraestrutura de execução: fila persistente, workers, eventos por WebSocket, recuperação e cancelamento — testada com jobs falsos, antes de plugar o pipeline real.

## Escopo
- `pipeline/queue.py` — `JobRunner` ([ADR 0003](../decisions/0003-banco-como-verdade-e-fila.md)): enfileirar, pegar próximo, atualizar estado/progresso **no banco**, concluir/falhar; worker GPU (concorrência 1) e worker leve; iniciado/parado no `lifespan` do FastAPI.
- Recuperação no startup: jobs `running` → reenfileirar (até N tentativas) ou `failed` com `error_code=interrupted`.
- Cancelamento: `DELETE /api/jobs/{id}` marca cancelado e encerra o processo/handle em execução (interface `CancellableTask` para a F2b implementar com subprocess).
- `services/events.py` — EventBus: publica eventos (`session.updated`, `job.progress`, `export.updated`) após cada escrita no banco; `GET /ws` (um socket por cliente, recebe eventos de todas as sessões; o frontend filtra).
- Posição na fila e ETA: calculadas a partir da tabela `jobs` (ETA por média móvel de duração dos últimos jobs, por etapa).
- Rotas: `GET /api/jobs` (fila atual com posição/ETA), `POST /api/sessions/{id}/process` (confirma rascunho e enfileira), `POST /api/sessions/{id}/reprocess` (**recusa** se já houver job ativo — 409), `DELETE /api/jobs/{id}`, `POST /api/jobs/{id}/discard` (descartar job falho).
- Handler de job **falso** para testes e para desenvolvimento do frontend (`STEMMA_FAKE_PIPELINE=1`): simula download/separação com progresso em ~20s.
- Testes: ordem da fila, concorrência 1 no GPU, recuperação após "restart" (recriar runner com jobs running no banco), cancelamento, guarda de reprocess, eventos chegando no WebSocket (TestClient websocket).

## Fora do escopo
yt-dlp, Demucs, ffmpeg reais (F2b).

## Checklist
- [x] JobRunner + workers + lifespan
- [x] recuperação no startup
- [x] cancelamento + descartar
- [x] EventBus + `/ws`
- [x] posição na fila + ETA
- [x] rotas process/reprocess/jobs
- [x] pipeline falso via env
- [x] testes listados acima

## Critério de pronto
Com o pipeline falso: enfileirar 2 sessões mostra a 2ª como "Na fila · 1º" com ETA; matar e reiniciar o servidor no meio retoma/falha corretamente; eventos chegam no WebSocket; CI verde.

## Handoff
**Status:** concluída em 2026-10-05, PR #7 (`feat: fila de jobs e eventos ao vivo (F2a)`) com CI verde (`backend`, `frontend`, `pr-title`), aguardando o merge.

### Feito
- **Migration `0002`**: `jobs` ganhou `stage`, `stage_started_at`, `stage_durations` (JSON) e `dismissed_at`.
- **`pipeline/queue.py`**:
  - `JobRunner` com workers em threads: `gpu` (process, 1 por vez) e `light` (export), iniciados/parados no lifespan;
  - claim atômico, recuperação no startup (`JOB_MAX_ATTEMPTS`, padrão 2; depois `interrupted`) e parada limpa (devolve o job sem gastar tentativa);
  - `JobContext` (`set_stage`, `progress`, `sleep`, `check_cancelled`, `attach`) e `CancellableTask`.
- **`pipeline/eta.py`**: posição (a partir de 1, por worker) e ETA até terminar, por média móvel dos últimos 10 jobs `done`. A média é guardada como razão s/s de áudio; sem duração, segundos absolutos; sem histórico, padrões.
- **`pipeline/fake.py`** (`STEMMA_FAKE_PIPELINE=1`, `FAKE_PIPELINE_SECONDS`, padrão 20): download 30% + separação 70%; título com `[falha]` falha com `fake_failure`.
- **`services/events.py`**:
  - `EventBus` thread-safe;
  - `EventPublisher` em melhor esforço (falha só loga);
  - **`services/jobs.py`**: process, reprocess, list, cancel, discard.
- **Rotas**:
  - `POST /api/sessions/{id}/process|reprocess` (201 → `JobOut`);
  - `GET /api/jobs`, `DELETE /api/jobs/{id}` (204), `POST /api/jobs/{id}/discard` (204);
  - `GET /ws`.
- `SessionService` publica eventos em criar, editar e excluir.
- `utcnow()` com resolução de µs no Windows (ver Decisões).
- 139 testes (pytest). Os novos ficam em:
  - `test_queue`, `test_jobs_api`, `test_eta`;
  - `test_events_ws`, `test_fake_pipeline`, `test_clock`.
- **Verificação manual** com uvicorn real + pipeline falso:
  1. 2 sessões na fila: a 2ª fica com `position=1` e ETA.
  2. `taskkill /F` durante a separação + restart: o job voltou com `attempt` 2; uma segunda queda o fez falhar como `interrupted`.
  3. O cancelamento deixou a sessão `failed`/`cancelled`.
  4. Eventos chegando por um cliente `websockets`.
  5. Com histórico, o ETA bateu com o tempo real (~22 s para o job de 20 s).

### Contrato da API (para F2b/F3)
- **Eventos do `/ws`**: `{"type", "data"}`, tipados em `components["schemas"]["LiveEvent"]` do `schema.d.ts`.
  - `session.updated {session}`, `session.deleted {id}` e `job.updated {job}`;
  - cada evento é o **estado atual** da entidade no banco (pode chegar "adiantado"), não uma transição;
  - a cada mudança na fila, todos os jobs ativos são republicados com posição e ETA novos.
- **`JobOut`**:
  - `stage` + `progress` (0–100 **da etapa**); a sessão espelha os dois em `state`/`progress`, o que dá o chip "Separando 62%";
  - `position` (null se rodando), `eta_s` (null se encerrado), `dismissed_at`, e a `session` embutida.
- **`GET /api/jobs`**: rodando, depois a fila, depois até 10 encerrados (`done`/`failed`) não descartados. O dock mostra "pronto com Abrir mixer" e "falha com Tentar de novo/Descartar".
- **Erros 409**:
  - process: `session_not_draft`;
  - reprocess: `session_not_processed` (rascunho) ou `session_busy` (já na fila);
  - cancel: `job_not_active`;
  - discard: `job_not_dismissable`.
- **Cancelar** (decisão do usuário): a sessão vira `failed` com `error_code=cancelled` ("Processamento cancelado."), mesmo num reprocess de sessão pronta. Reprocessar uma sessão descarta (`dismissed_at`) os jobs encerrados anteriores dela.
- **"Tentar de novo"** = `POST /reprocess`.
- **Sem `STEMMA_FAKE_PIPELINE`** e antes da F2b, o job falha com `pipeline_unavailable`.
- **`export.updated`** existe no enum `EventType`, mas só entra na união `LiveEvent` na F2b, junto com o `ExportOut`.

### Para a F2b
- Registrar os handlers reais em `default_job_handlers` (`app/main.py`).
- No handler: `ctx.set_stage(DOWNLOADING|SEPARATING)`, `ctx.progress(pct)`, `ctx.attach(task)`, com `task.cancel()` matando o subprocess. Ao ser cancelado/desligado, levantar qualquer erro (ou `JobCancelledError`); o runner distingue pelo `ctx.cancelled`.
- `ctx.session` traz `source_url`, `title`, `duration_s` etc.
- Gravar `stems`/`metrics` na sessão é responsabilidade do handler (o runner só põe `ready`/`processed_at`). A limpeza dos stems antigos no reprocess também é da F2b.

### Pendente
- Itens herdados: teste no celular via Tailscale e branch protection (F0).

### Decisões
- [ADR 0009](../decisions/0009-workers-em-threads-e-eventos.md):
  - workers em threads e escritas condicionais a `running`;
  - EventBus thread-safe e `job.updated` no lugar de `job.progress`;
  - `session.deleted` novo e relógio de µs.
- **Jobs `done`** também aparecem no dock até serem descartados (o design pede "pronto com Abrir mixer"); o discard aceita `done` e `failed`.
- **Pipeline falso com falha simulada** por `[falha]` no título (decisão do usuário).

### Pegadinhas
- **Relógio do Windows**: no Python 3.12, `datetime.now()` anda em degraus de 15,6 ms. Use **sempre** `app.db.types.utcnow()`. Os testes de ordenação da F1 que falhavam de forma intermitente no Windows eram isso.
- **TestClient**: os eventos são montados no momento da publicação. Em testes de WS, não presuma que o primeiro evento seja `queued`, porque o worker pode já ter pego o job.
- **Testes da fila**: usam `tests/fakes.ControlledHandler`, em que o job só termina com `finish()`/`fail()`, e `wait_until`; nada de `sleep` fixo. O fixture `client` padrão roda sem handlers (job falha com `pipeline_unavailable`).
- **Matar o servidor no Windows**: use `taskkill /F /T` no PID do `uv`. Sem `/T`, o python filho continua com a porta aberta.

### Pendências descobertas
- Nenhuma fora do escopo das próximas fases.
