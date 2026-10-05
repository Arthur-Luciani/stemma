# 0003 — Banco como fonte da verdade e fila de jobs persistente

- **Status:** aceita (2026-10-05)

## Contexto
Na v1, o estado dos jobs vivia num cache em memória que divergia do SQLite; jobs longos de GPU rodavam via `BackgroundTasks` sem fila, sem limite de concorrência e sem recuperação após restart.

## Decisão
- Todo estado (sessões, jobs, progresso, exports) é gravado no SQLite; leituras vão ao banco.
- Tabela `jobs` como fila (`kind`, `session_id`, `state`, `progress`, `attempt`, `error`, timestamps). Um worker de GPU (concorrência 1) e um worker leve (ffmpeg/export).
- No startup, jobs `running` são reenfileirados ou marcados como `failed` ("interrompido").
- EventBus em memória só **propaga** eventos para WebSockets; nunca é fonte de estado.
- SQLite com WAL, `busy_timeout` e `PRAGMA foreign_keys=ON`.

## Consequências
Restart seguro, posição na fila e ETA calculáveis, cancelamento possível. Exige um único processo (ver 0002).
