# F5 — Runtime, PWA e atualização

## Objetivo
Stemma rodando como serviço no PC, acessível pelo celular via HTTPS, instalável como app, com atualização e rollback automáticos ([ADR 0002](../decisions/0002-runtime-nativo-windows.md), [ADR 0007](../decisions/0007-processo-de-release.md)).

## Escopo
- Backend serve `frontend/dist` (config `SERVE_FRONTEND_DIR`) com fallback SPA, cache headers corretos (assets com hash = imutável; `index.html` sem cache); bind `127.0.0.1`; CORS desligado em produção.
- `deploy/stemma-service.xml` (WinSW): executável, args, env (`.env`), conta do usuário, restart on failure, logs com rotação.
- `deploy/start.ps1`: carrega `.env`, `alembic upgrade head`, inicia uvicorn (1 worker).
- `deploy/install.ps1`: primeira instalação (pastas `C:\stemma\{releases,venv}`, `D:\stemma-data`, venv com `uv sync --all-groups`, registra o serviço, configura `tailscale serve --bg https / http://127.0.0.1:8000`).
- `deploy/update.ps1`: fluxo completo da ADR 0007 (download + SHA256, extração lado a lado, `uv sync`, parar serviço, backup do banco via SQLite backup API, migration, junction `current`, start, poll do `/health` pela versão, rollback automático), retenção de 3 releases, flags `-Version`, `-YtDlpOnly`, `-Rollback`.
- Release zip passa a conter `deploy/` e é testado pelo `update.ps1`.
- **PWA**: `vite-plugin-pwa` com manifest (nome Stemma, cores, `display: standalone`), ícones gerados a partir da marca (512/192/maskable, apple-touch-icon, favicon 32/16), service worker só do app shell (nunca stems/API); aviso "Nova versão disponível — recarregar".
- Documentação: `docs/operacao.md` (instalar, atualizar, rollback, logs, cookies do YouTube, checklist de smoke manual pós-update).

## Fora do escopo
Novas funcionalidades.

## Checklist
- [x] SPA servida pelo FastAPI com cache correto
- [x] WinSW + start.ps1 + install.ps1 (ensaio real no PC depende da release)
- [x] update.ps1 com backup, migration e rollback (ensaio real no PC depende da release)
- [x] tailscale serve configurado (pelo install.ps1) e documentado
- [ ] PWA instalável no Android (sem erros de instalabilidade no Edge; falta instalar no celular) — iPhone sem aparelho
- [x] docs/operacao.md com smoke checklist
- [x] Modo app no PWA instalado: sem seleção/menu ao segurar, sem pinch zoom (pedido do usuário na sessão)

## Critério de pronto
Instalar a **primeira release com `deploy/`** (a da F5; as releases até a v1.2.0 não têm `deploy/` no zip) a partir do zip da GitHub Release com `install.ps1`; publicar a **release seguinte**; rodar `update.ps1` e ver a nova versão no `/health` sem passo manual; simular falha (`-SimulateFailure`) e ver o rollback; app instalado na tela inicial do celular abrindo via `https://<pc>.<tailnet>.ts.net`.

_Critério reescrito com o usuário em 2026-10-06 (antes: v1.0.0 → v1.0.1)._

## Handoff
_Preencher ao final da sessão._
