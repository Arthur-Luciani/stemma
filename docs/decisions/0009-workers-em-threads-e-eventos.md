# 0009 — Workers em threads, eventos ao vivo e relógio de alta resolução

- **Status:** aceita (2026-10-05)
- Complementa a [0003](0003-banco-como-verdade-e-fila.md).

## Contexto
A F2a implementou a fila da ADR 0003. Os handlers do pipeline são bloqueantes (subprocess na F2b) e o SQLAlchemy é síncrono. Os eventos precisam sair das threads de trabalho e chegar a WebSockets que vivem no event loop do uvicorn. Além disso, no Windows com Python 3.12, o relógio de parede anda em degraus de 15,6 ms. Com isso, jobs e sessões criados em sequência empatavam no `created_at`, e a ordem da fila ficava aleatória.

## Decisão

### Workers
- Cada worker é uma **thread daemon** com a sua sessão de banco (`pipeline/queue.py`):
  - `gpu` executa `process`, um job por vez;
  - `light` executa `export`.
- Os workers são iniciados e parados no `lifespan`.
- **Claim atômico** com `UPDATE … WHERE id = (SELECT … LIMIT 1) AND state='queued' RETURNING`.
- Toda escrita do runner é **condicional a `state='running'`**: o cancelamento gravado pela API nunca é sobrescrito.
- **Interface para o pipeline**: `JobHandler.run(ctx)`. O `JobContext` oferece:
  - `set_stage`, `progress` (gravação espaçada em 0,5 s);
  - `sleep`, `check_cancelled`;
  - `attach(CancellableTask)`: cancelar chama `task.cancel()` (na F2b, matar o subprocess).
- **Restart**:
  - **parada limpa**: o shutdown devolve o job em execução para a fila sem gastar tentativa;
  - **queda**: um job `running` encontrado no startup volta para a fila até `JOB_MAX_ATTEMPTS`, e depois falha com `interrupted`.

### Eventos
- O **EventBus** é thread-safe. Cada assinante tem uma `asyncio.Queue` presa ao seu loop, e o `publish` usa `call_soon_threadsafe`. A fila é limitada (500); se encher, o mais antigo é descartado. Nada fica guardado.
- O **`EventPublisher`** é o único que monta eventos, com os schemas da API. É chamado **depois do commit** e lê o estado atual do banco.
- Os eventos são `session.updated`, `session.deleted` e `job.updated`:
  - `job.updated` substitui o `job.progress` previsto no plano, porque também cobre transições e cancelamento;
  - a cada mudança na fila, todos os jobs ativos são republicados com posição e ETA atualizados.
- Formato no `/ws`: `{"type", "data"}`. O tipo `LiveEvent` entra no OpenAPI para gerar o TS.

### Relógio
- `app.db.types.utcnow()` = âncora do relógio de parede + `perf_counter` (resolução de µs), reancorado se os dois divergirem mais de 1 s. É o único relógio do app.

## Consequências
- Ordem FIFO confiável e listas "mais recentes" estáveis no Windows.
- A F2b só implementa handlers e `CancellableTask`; fila, eventos e recuperação já estão prontos.
- Um evento pode chegar já "adiantado", porque reflete o banco na hora da publicação. O frontend trata cada evento como o estado mais recente da entidade, não como uma transição.
