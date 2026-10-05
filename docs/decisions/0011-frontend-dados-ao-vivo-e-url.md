# 0011 — Frontend: client tipado, eventos ao vivo no cache e estado de overlays na URL

- **Status:** aceita (2026-10-05)
- **Complementa:** [ADR 0005](0005-frontend-stack.md)

## Contexto
A F3 fez as telas fora do mixer (Descobrir, Processamento, Biblioteca). A ADR 0005 já previa três coisas:
- client tipado pelo OpenAPI;
- TanStack Query atualizado pelo WebSocket;
- toda tela com URL.

Faltava decidir *como* fazer cada uma, e o "back do Android tem que funcionar" pesa sobre sheets e diálogos, que não são telas.

## Decisão

### Client
- **`openapi-fetch`** sobre o `schema.d.ts` gerado.
- `src/api/client.ts` normaliza qualquer falha em `ApiError {status, code, message}`:
  - o `{"error": {...}}` do backend;
  - um corpo fora do padrão vira `unknown_error`;
  - falha de rede vira `network_error`.
- `src/api/endpoints.ts` tem uma função por rota; é o único lugar que chama o client.
- Queries só tentam de novo em `network_error`, porque erro da API é definitivo.

### Eventos ao vivo (`/ws`)
- Um `LiveConnection` por app, aberto no layout. Reconecta com backoff exponencial (1 s → 30 s, jitter de ±20%).
- `createLiveEventHandler` aplica cada evento no cache:
  - `session.updated` → `setQueryData` do detalhe e da sessão embutida nos jobs;
  - `job.updated` → upsert/remoção na lista `['jobs']`, com o mesmo filtro do `GET /api/jobs` (sai se descartado ou cancelado; export só enquanto ativo);
  - `session.deleted` → remove o detalhe e os jobs da sessão.
- **Listas de sessões não são recalculadas no cliente**, porque filtro, busca, ordenação e contagens são do servidor. Elas são invalidadas com debounce de 400 ms, para não refazer o GET a cada %.
- **Na reconexão, `invalidateQueries()` em tudo**, porque eventos podem ter se perdido na queda. O banco continua sendo a verdade (ADR 0003).

### Estado de overlays na URL
- Sheets e diálogos que o usuário abre ficam na query string, via `useUrlParam`:
  - `?pick=` (identidade no celular);
  - `?jobs=1` (sheet de processamento);
  - `?act=menu|edit|delete:<id>` (ações da biblioteca).
- **Abrir empilha uma entrada** no histórico e marca o `state`; **fechar volta** (`navigate(-1)`) só se foi esse componente que empilhou. Senão, remove o parâmetro com `replace`.
- Trocar de um overlay para outro do mesmo parâmetro (menu → excluir) substitui a entrada.
- No desktop, escolher um resultado só troca o card (`replace`): não há overlay para o back fechar.
- Busca da Biblioteca, filtro e ordenação também ficam na URL (com `replace`); a busca do Descobrir empilha (`?q=`).

## Consequências
- O back do Android fecha sheets e diálogos antes de sair da tela, e um link compartilhado/recarregado reabre o mesmo estado.
- O cache fica correto sem polling. O custo é um GET de lista a cada rajada de eventos.
- Quem cria um overlay novo deve usar `useUrlParam` (com `replace` quando não houver o que fechar com o back), senão o back sai da tela.
