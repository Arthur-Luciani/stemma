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
- [ ] JobRunner + workers + lifespan
- [ ] recuperação no startup
- [ ] cancelamento + descartar
- [ ] EventBus + `/ws`
- [ ] posição na fila + ETA
- [ ] rotas process/reprocess/jobs
- [ ] pipeline falso via env
- [ ] testes listados acima

## Critério de pronto
Com o pipeline falso: enfileirar 2 sessões mostra a 2ª como "Na fila · 1º" com ETA; matar e reiniciar o servidor no meio retoma/falha corretamente; eventos chegam no WebSocket; CI verde.

## Handoff
_Preencher ao final da sessão._
