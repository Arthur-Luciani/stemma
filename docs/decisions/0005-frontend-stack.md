# 0005 — Frontend: React + TypeScript, Router, TanStack Query, CSS Modules com tokens

- **Status:** aceita (2026-10-05); detalhada pela [ADR 0011](0011-frontend-dados-ao-vivo-e-url.md) (client, eventos ao vivo no cache, overlays na URL)

## Contexto
A v1 não tinha roteador (página em `useState`), tinha estado de sessão triplicado em contexts, um god-hook de 370 linhas, CSS global de 1.960 linhas com cores soltas e nenhum lint/teste.

## Decisão
- React 18 + **TypeScript** + Vite. **React Router** (toda tela com URL). **TanStack Query** para server state; eventos do WebSocket atualizam o cache.
- Client de API tipado com tipos gerados do OpenAPI (`openapi-typescript`), commitados e checados no CI.
- Estrutura `api/` → `features/` → `ui/`; `audio/` fora do React.
- **CSS Modules** + design tokens em custom properties (ver `docs/design/README.md`). Mobile-first.
- ESLint (typescript-eslint, `react-hooks/exhaustive-deps` como erro), Prettier, Vitest + Testing Library.
- PWA via `vite-plugin-pwa` (só app shell, nunca stems).

## Consequências
Contrato backend↔frontend verificado no CI; padrões impostos por ferramenta, não por memória.
