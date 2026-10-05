# F3 — Frontend: Descobrir, Processamento e Biblioteca

## Objetivo
Fluxos fora do mixer funcionando no desktop e no celular, seguindo o design.

Antes de começar: ler [docs/design/README.md](../design/README.md) e abrir os arquivos `Stemma - Celular` (M1–M5) e `Stemma - Desktop` no Claude Design.

## Escopo
- **Base**: React Router com rotas `/` (Descobrir), `/sessions` (Biblioteca), `/sessions/:id` (detalhe/acompanhar; o `ST-###` só é exibido), `/sessions/:id/mix` (placeholder até F4); TanStack Query; client `src/api/` tipado pelo OpenAPI; tratamento de erro padronizado (`{error:{code,message}}` → toast/estado de erro); ErrorBoundary.
- **Eventos ao vivo**: hook `useLiveEvents` (um WebSocket, reconexão com backoff) que atualiza o cache do Query.
- **Design system (`src/ui/`)**: Button, SegmentedControl, StatusChip, SessionCard/SessionRow, Toast, Dialog, BottomSheet, Menu, Skeleton, EmptyState, ErrorState, ícones Material Symbols — conforme tokens; cada componente com teste básico.
- **Layout**: desktop com topbar (Descobrir · Biblioteca · Mixer); celular com bottom nav; safe areas; Mixer na navegação aponta para a última sessão aberta.
- **Descobrir**: busca (texto ou colar link), "Continuar de onde parou" (sessões recentes), resultados (skeleton, vazio, erro com "Tentar de novo"), identidade (card no desktop / bottom sheet no celular) com autocomplete de artista + contagem, previsão de fila, botão Separar.
- **Processamento**: dock recolhível (desktop) e pílula + sheet (celular): job atual com etapas e %, ETA, Cancelar; fila com posição; falha com Tentar de novo/Descartar; pronto com Abrir mixer.
- **Biblioteca**: busca (`/` foca no desktop), filtros por estado com contagem, ordenação, paginação/scroll infinito; tabela (desktop) e cards (celular); ação principal contextual + menu ⋯ (Editar artista e título, Reprocessar, Excluir com Dialog).
- Textos centralizados em `src/strings.ts` (PT-BR).
- Desenvolvimento contra backend com `STEMMA_FAKE_PIPELINE=1` se a F2b não estiver pronta.
- Testes: componentes `ui/`, hooks de dados com MSW ou mocks do client, fluxo Descobrir → Separar.

## Fora do escopo
Mixer, AudioEngine, export (F4), PWA (F5).

## Checklist
- [x] router + query + client + erros + ErrorBoundary
- [x] useLiveEvents
- [x] componentes ui/ com testes
- [x] layout desktop/celular
- [x] Descobrir completo (todos os estados)
- [x] Processamento (dock + pílula/sheet)
- [x] Biblioteca completa
- [x] strings PT-BR centralizadas
- [x] conferido no celular real via Tailscale (retrato) e no desktop

## Critério de pronto
Pelo celular (via Tailscale, dev server): buscar, confirmar identidade, acompanhar o processamento ao vivo, gerenciar a biblioteca — sem layout quebrado, back do Android funcionando; CI verde.

## Handoff
**Status:** concluída em 2026-10-05. PR #10 (`feat: frontend de descobrir, processamento e biblioteca (F3)`) com CI verde. Conferida pelo usuário no celular real (Android) via Tailscale.

### Feito
- **Base**:
  - `src/api/`:
    - `client.ts` usa `openapi-fetch` e normaliza erros em `ApiError {status, code, message}` (`network_error` sem rede);
    - `endpoints.ts` tem uma função por rota;
    - `live.ts` tem o `LiveConnection` (WebSocket com backoff 1–30 s e jitter);
    - `types.ts` tem os aliases e `counts` como `Record<SessionState, number>`.
  - `src/app/`:
    - rotas `/`, `/sessions`, `/sessions/:id`, `/sessions/:id/mix` (placeholder) e `*` 404;
    - QueryClient (retry só em `network_error`, `staleTime` de 30 s);
    - `RouteError` (`errorElement`) e `RootErrorBoundary`;
    - toasts de erro padronizados (`useErrorToast`).
- **Ao vivo**: `useLiveEvents` + `createLiveEventHandler` (ver [ADR 0011](../decisions/0011-frontend-dados-ao-vivo-e-url.md)).
- **Design system `src/ui/`**, cada componente com teste:
  - Button/ButtonLink, SegmentedControl (segmented e chips), StatusChip;
  - Toast (+ `toastContext`), Modal → Dialog e BottomSheet (+ SheetAction), Menu;
  - Skeleton, EmptyState/ErrorState, TextField, ProgressBar, Spinner, Icon;
  - `cx`, `useMediaQuery` (desktop ≥ 900px).
  - Tokens novos em `tokens.css`: overlay, sombras, `--bg-nav`, listras da miniatura, z-index, alturas de topbar/nav.
- **Layout**:
  - topbar (desktop) e bottom nav (celular), com safe areas;
  - o Mixer da navegação aponta para a última sessão aberta (`localStorage`); sem nenhuma, leva à Biblioteca.
- **Descobrir**:
  - busca na URL (`?q=`), botão colar;
  - "Continuar de onde parou";
  - estados Skeleton, nenhum resultado, YouTube fora (Tentar de novo) e link inválido (422);
  - link colado já vem escolhido;
  - identidade no card (desktop) ou no sheet (celular), com autocomplete de artista + contagem e "já usado · N sessões" no desktop;
  - previsão de fila;
  - Separar = `POST /sessions` + `POST /process`. Se o process falhar, a sessão fica como rascunho e o toast oferece "Continuar".
- **Processamento**:
  - dock recolhível (desktop, preferência em `localStorage`) e pílula + sheet (celular, `?jobs=1`);
  - etapas Baixado → Separando NN% → Pronto, ETA, Cancelar;
  - fila com posição e "começa em ~X";
  - falha com Tentar de novo/Descartar; pronto com Abrir mixer.
- **Biblioteca**:
  - busca (`/` foca no desktop), filtros com contagem e ordenação, tudo na URL;
  - scroll infinito + "Carregar mais"; tabela (desktop) e cards (celular);
  - ação principal contextual;
  - menu ⋯ (desktop) ou sheet de ações (celular): Editar (Dialog), Reprocessar, Excluir (Dialog; 409 `session_busy` vira toast).
- **Detalhe `/sessions/:id`**: rascunho (identidade + Separar), em andamento (card do job), falhou (Tentar de novo), pronta (Abrir mixer).
- **Textos** em `src/strings.ts`; formatadores em `src/lib/format.ts`.
- **Testes**: 81 (Vitest + Testing Library + MSW 2), em 19 arquivos:
  - `ui/`;
  - client, `LiveConnection`, `applyLiveEvent`, formatadores;
  - rotas/layout;
  - fluxos Descobrir → Separar, Processamento, Biblioteca e detalhe;
  - regressões do review.
- **Verificação manual** com backend real e `STEMMA_FAKE_PIPELINE=1`, busca real no YouTube, Edge via Playwright em 1440×900 e 390×844 (touch):
  - buscar, escolher, Separar → toast;
  - dock e pílula ao vivo; falha simulada (`[falha]`);
  - excluir em processamento → toast do 409;
  - sheet de ações e diálogo de edição no celular;
  - back fechando sheets e diálogos.
- **`/code-review`**: 4 achados, todos corrigidos com teste de regressão:
  - link colado reabria o sheet/card sozinho (e permitia separar em dobro);
  - sheet de processamento ficava "aberto" na URL depois de descartar o último job;
  - a busca da biblioteca comia o espaço final;
  - Reprocessar pelo sheet do celular não fechava o sheet.

### Pendente
- Herdado: branch protection (F0). A pendência da F0 de testar no celular via Tailscale fechou nesta fase.

### Decisões
- [ADR 0011](../decisions/0011-frontend-dados-ao-vivo-e-url.md):
  - `openapi-fetch`;
  - eventos do `/ws` aplicados no cache (listas invalidadas com debounce; tudo invalidado na reconexão);
  - sheets e diálogos na URL, para o back funcionar.
- Desvios do design registrados em [docs/design/README.md](../design/README.md#desvios):
  - sem prever o `ST-###`;
  - previsão "começa em" no lugar de "pronto em";
  - tela de detalhe própria;
  - sem Duplicar;
  - chips com alvo de 44px;
  - ordenação no celular;
  - botão "colar link".
- **Abrir mixer** num job pronto (dock/sheet) também o descarta da lista: abrir conta como "visto".
- Breakpoint único de **900px** (`useIsDesktop`): troca topbar/bottom nav, tabela/cards, card/sheet e dock/pílula.
- Dependências novas:
  - `react-router` 7, `@tanstack/react-query` 5 e `openapi-fetch`;
  - dev: `msw` 2 e `@testing-library/user-event`.

### Pegadinhas
- **Acesso pelo celular**: use `https://<máquina>.<tailnet>.ts.net:5183`, com `https` e a porta, e o app do Tailscale ligado. Se não abrir, confira:
  - `tailscale status` (o celular aparece `active`);
  - `tailscale serve status` (proxy para `http://127.0.0.1:5183`);
  - DNS privado ou outra VPN no Android, que podem impedir o nome `.ts.net` de resolver.
- **MSW 2 também substitui o `WebSocket` global** no `server.listen()`. O `FakeWebSocket` dos testes é instalado com `vi.stubGlobal` **depois** do `listen` (`src/test/setup.ts`); antes disso, o stub é sobrescrito. Atribuir `globalThis.WebSocket = …` direto não funciona no jsdom.
- O `openapi-fetch` recebe `fetch: (r) => globalThis.fetch(r)`: o global é lido a cada chamada, porque o MSW troca o `fetch` depois dos imports. O `baseUrl` é `window.location.origin`, porque o Node não aceita URL relativa.
- **Callbacks passados ao `mutate(..., {onSuccess})` não disparam se o componente desmontar antes da resposta.** Feche sheets e diálogos no `onSettled`, não antes de chamar a mutation.
- **`useUrlParam`**:
  - abrir empilha e marca `state.urlParam`; fechar só faz `navigate(-1)` se a entrada foi empilhada por ele;
  - com `replace`, não marque, senão o "fechar" sai do app (esse bug apareceu no Separar do desktop).
- O lint (`react-hooks` 7) proíbe `setState` síncrono dentro de `useEffect` e ler ref durante o render. Para "fazer só uma vez", use ref lido e escrito **dentro** do efeito; para sincronizar campo com URL, use o padrão de comparar com o valor anterior no render (`SearchBox`, `LibraryPage`).
- **Screenshots locais**: o Edge headless (`--screenshot`) não respeita larguras abaixo de ~500px, e o iframe em `file://` sai em branco. Use `playwright-core` com `channel: 'msedge'` (sem baixar navegador), com `isMobile`/`hasTouch`. No Git Bash, rode com `MSYS_NO_PATHCONV=1`, senão `/` vira `C:/Program Files/Git/`.

### Pendências descobertas
- Nenhuma fora do escopo das próximas fases.
