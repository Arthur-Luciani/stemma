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
- [x] PWA instalável (sem erros de instalabilidade no Edge headless); instalação no celular conferida na F5b — iPhone sem aparelho
- [x] docs/operacao.md com smoke checklist
- [x] Modo app no PWA instalado: sem seleção/menu ao segurar, sem pinch zoom (pedido do usuário na sessão)

## Critério de pronto
Instalar a **primeira release com `deploy/`** (a da F5; as releases até a v1.2.0 não têm `deploy/` no zip) a partir do zip da GitHub Release com `install.ps1`; publicar a **release seguinte**; rodar `update.ps1` e ver a nova versão no `/health` sem passo manual; simular falha (`-SimulateFailure`) e ver o rollback; app instalado na tela inicial do celular abrindo via `https://<pc>.<tailnet>.ts.net`.

_Critério reescrito com o usuário em 2026-10-06 (antes: v1.0.0 → v1.0.1)._

## Handoff
**Status:** concluída — PR #16 (mergeado em 2026-10-06), release **v1.3.0** (primeira com `deploy/` no zip).
O ensaio real do critério de pronto (instalar, atualizar, simular falha, PWA no celular) **passou para a [F5b](F5b-instalador.md)**, por decisão do usuário: instalar por script ficou difícil, e o instalador vai embrulhar a mesma lógica. O que ficou validado nesta fase está em "Feito" (ensaio sem o serviço, Edge headless, CI).

### Feito
- **SPA servida pelo backend** (`app/spa.py`, `SERVE_FRONTEND_DIR`):
  - rota coringa registrada depois dos routers;
  - arquivo do `dist` servido como está; qualquer outro path vai para o `index.html`;
  - `/api`, `/ws` e `/health` nunca caem no fallback (404 JSON);
  - cache: `assets/*` `immutable`; `index.html`, `sw.js`, `manifest.webmanifest` e `workbox-*` `no-cache`; ícones 1 dia;
  - aceita `HEAD`; path fora do `dist` é bloqueado.
- **Backup do banco**: `python -m app.cli backup --dest` / `restore --src` (`services/backup.py`, API de backup do SQLite). O backup é escrito num `.partial` e só depois renomeado.
- **Deploy** (`deploy/`, ADRs [0002](../decisions/0002-runtime-nativo-windows.md) e [0007](../decisions/0007-processo-de-release.md) atualizadas):
  - `StemmaDeploy.psm1` com as funções compartilhadas;
  - `stemma-service.xml`: WinSW 2.12 com SHA256 fixado, conta do usuário via `install /p`, restart on failure, logs com rotação;
  - `start.ps1`, `install.ps1` e `update.ps1` (`-Version`, `-ZipPath`, `-Rollback`, `-YtDlpOnly`, `-SimulateFailure`);
  - **um venv por release**;
  - Pester 5 (31 testes) no job novo `deploy` do CI.
- **PWA**:
  - `vite-plugin-pwa` (`registerType: 'prompt'`); o SW guarda só o app shell e nunca a API/stems;
  - manifest `standalone` com fundo `#121416`;
  - ícones 192/512 "any", 512 maskable, apple-touch 180 e favicon 16/32, gerados por `npm run gen:icons` a partir de `public/favicon.svg` e `pwa/icon-maskable.svg`;
  - metas `apple-mobile-web-app-*`;
  - toast persistente "Nova versão disponível · Recarregar" (`UpdatePrompt`), com checagem de hora em hora;
  - instalado: o `Toast` ganhou `persistent`, que não é descartado pelo limite de 3.
- **Modo app** (pedido na sessão; só com `display-mode: standalone`):
  - sem seleção de texto ao segurar, sem menu do toque longo, sem arrastar imagem e sem pinch zoom (`lib/standaloneMode.ts` + `global.css`);
  - campos de texto continuam normais;
  - o duplo toque não dá zoom em nenhum modo (`touch-action: manipulation`);
  - "puxar para atualizar" ficou como estava (decisão do usuário).
- **Conferido localmente**:
  - backend servindo o `dist`: headers de cache via `curl`;
  - Edge headless (CDP): SW ativo, manifest sem erros e `Page.getInstallabilityErrors` vazio.
- **Ensaio do deploy sem o serviço** (a sessão não era admin): pacote montado como o `release.yml` → `Get-StemmaPackage` (SHA256) → `Expand-StemmaPackage` → `uv sync` (14 s, torch do cache) → `start.ps1` com a saída redirecionada → `/health` 1.2.0.
  - Depois, sequência do update para um pacote "v1.2.1": backup → `alembic upgrade` → junction → `/health` 1.2.1, com os dados preservados.
  - Por fim, rollback: restore → junction de volta → `/health` 1.2.0.
- **`/code-review`**: 5 achados, todos corrigidos:
  - backup que falhava no meio deixava um arquivo vazio que o rollback restaurava por cima do banco;
  - `GetFileName` não separa `\` no pwsh do Linux (o CI quebraria);
  - o toast de versão nova podia ser descartado;
  - os prompts do WinSW ficavam presos no pipe;
  - uma falha no `-Rollback` manual deixava o serviço parado.

### Pendente
- **Critério de pronto real → F5b**: instalar no PC, atualizar para a release seguinte, simular falha e ver o rollback, PWA instalado no celular. Na F5b isso é feito pelo instalador, que reaproveita `deploy/StemmaDeploy.psm1`.
- Ao instalar o PWA de produção: remover o atalho antigo (`:5183`, é outra origem).
- iPhone: sem aparelho. As metas e o apple-touch-icon estão lá; não há splash própria no iOS.
- Herdados: medição do AudioEngine no Android (F4a), branch protection (F0).

### Decisões
- Venv por release, backup/restore pelo app, rollback por restore (automático) ou downgrade (manual): [ADR 0007](../decisions/0007-processo-de-release.md#atualização-f5-2026-10-06).
- Critério de pronto reescrito: primeira release com `deploy/` → seguinte. Depois transferido para a F5b (instalador).
- Desvios do design (ícone maskable sem borda, splash, modo app) em [docs/design/README.md](../design/README.md#desvios).

### Pegadinhas
- **Windows PowerShell 5.1 + stderr de executável**: com a saída redirecionada (serviço, pipe), cada linha de stderr vira `ErrorRecord`. Com `$ErrorActionPreference='Stop'`, o log do uv/alembic derrubava o script. O `Invoke-Native` roda com `Continue`, junta stdout e stderr e decide só pelo exit code. Apareceu no ensaio.
- **`.ps1`/`.psm1` com BOM** (senão os acentos quebram no 5.1). O Pester confere. Edite com cuidado: o editor pode tirar o BOM.
- `-Skip:` do Pester é avaliado na descoberta. Variável usada nele vai em `BeforeDiscovery`, não em `BeforeAll`.
- O módulo virtual `virtual:pwa-register/react` não existe no Vitest. Há um alias para `src/test/pwaRegister.ts` (fake com `pwaFake.needRefresh(true)`).
- `SERVE_FRONTEND_DIR` relativo é a partir da **raiz do repo** (`frontend/dist`), não de `backend/`.
- O PWA da produção é outra origem (`https://<pc>…ts.net`, sem `:5183`): precisa reinstalar no celular.
- O release-please só abre release com commit `feat:`/`fix:` (ou breaking). `test:`, `docs:` e `chore:` não geram versão nova. Para testar o update é preciso um `fix:` real.
- `test_descartar_publica_job_com_dismissed_at` era intermitente (evento da falha chegando depois do `wait_until`); corrigido no PR #18.
- O Pester do Windows é o 3.4. Para rodar localmente: `Install-Module Pester -Scope CurrentUser` (pede o provedor NuGet, interativo) ou importe um Pester 5 baixado.

