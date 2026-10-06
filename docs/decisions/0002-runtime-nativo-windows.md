# 0002 — Runtime nativo no Windows, sem Docker

- **Status:** aceita (2026-10-05)

## Contexto
O app roda num único PC Windows 11 com GPU NVIDIA e é acessado pelo celular via Tailscale. A stack usa torch cu118 + Demucs + ffmpeg.

## Decisão
- Um processo **uvicorn (1 worker)** em `127.0.0.1:8000` serve `/api`, `/ws` e o `frontend/dist` (SPA fallback) na mesma origem.
- Roda como **serviço Windows via WinSW** (XML versionado em `deploy/`), sob a conta do usuário, com restart on failure e logs rotacionados; config em `.env`.
- Acesso externo **só** por `tailscale serve` (HTTPS com certificado `*.ts.net`, necessário para PWA/Service Worker).
- Docker fora do escopo.

## Alternativas descartadas
Docker Desktop + WSL2 GPU: imagem de 6–10 GB, camada extra de driver/WSL para quebrar, I/O lento em bind-mount de `D:\`, e o setup nativo já funciona.

## Consequências
Sem CORS nem proxy em produção. O ambiente não é 100% reprodutível: Python, FFmpeg e Deno/Node são instalados manualmente e verificados no `/health`. Multi-worker é proibido (EventBus em memória).

## Atualização (F5, 2026-10-06)
- O serviço roda `current\deploy\start.ps1` (carrega `C:\stemma\.env`, `alembic upgrade head`, uvicorn com o Python do venv da release). O WinSW manda Ctrl+C primeiro (`stopparentprocessfirst`) e mata a árvore após 20 s.
- O backend serve o `frontend/dist` quando `SERVE_FRONTEND_DIR` está definido (`app/spa.py`): assets com hash `immutable`; `index.html`, `sw.js` e `manifest.webmanifest` com `no-cache`; `/api`, `/ws` e `/health` nunca caem no fallback da SPA.
- `tailscale serve --bg --https=443 http://127.0.0.1:8000` (o dev continua na `:5183`).
