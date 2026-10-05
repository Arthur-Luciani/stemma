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
- [ ] router + query + client + erros + ErrorBoundary
- [ ] useLiveEvents
- [ ] componentes ui/ com testes
- [ ] layout desktop/celular
- [ ] Descobrir completo (todos os estados)
- [ ] Processamento (dock + pílula/sheet)
- [ ] Biblioteca completa
- [ ] strings PT-BR centralizadas
- [ ] conferido no celular real via Tailscale (retrato) e no desktop

## Critério de pronto
Pelo celular (via Tailscale, dev server): buscar, confirmar identidade, acompanhar o processamento ao vivo, gerenciar a biblioteca — sem layout quebrado, back do Android funcionando; CI verde.

## Handoff
_Preencher ao final da sessão._
