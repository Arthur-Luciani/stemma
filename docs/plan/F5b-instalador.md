# F5b — Instalador

## Objetivo
Instalar e atualizar o Stemma no PC por um **instalador `.exe`**, sem rodar script à mão, inclusive com Tailscale. Embrulha a lógica da F5 (`deploy/StemmaDeploy.psm1`: backup, migrations, venv por release, rollback). Pedido do usuário em 2026-10-06, depois de achar a instalação por script difícil.

## Decisões já tomadas (com o usuário, 2026-10-06)
- **Serviço com conta do sistema (LocalSystem)**: a instalação não pede a senha do Windows. Por isso uv, Python, FFmpeg e Deno ficam em pastas do sistema (`C:\stemma\tools`), e não no perfil do usuário. Muda a [ADR 0002](../decisions/0002-runtime-nativo-windows.md) (hoje: "sob a conta do usuário") → ADR nova.
- **Atualização**: rodar o instalador da versão nova atualiza (com backup e rollback). O botão "Atualizar" dentro do app é a [F5c](F5c-atualizar-pelo-app.md).
- **Critério de pronto da F5 herdado** (instalar, atualizar, simular falha, PWA no celular), agora pelo instalador.

## Antes de começar
1. **Verificar o risco principal**: o torch enxerga a GPU (CUDA) num processo rodando como LocalSystem? Teste rápido com `psexec -s` ou com um serviço WinSW temporário rodando `python -c "import torch; print(torch.cuda.is_available())"`. Se **não** funcionar, pare e leve ao usuário (alternativa: conta de serviço virtual `NT SERVICE\stemma`, ou voltar à conta do usuário).
2. Ler o Handoff da [F5](F5-runtime-pwa.md) (pegadinhas do PowerShell 5.1: stderr de nativos, BOM, Pester) e o [docs/operacao.md](../operacao.md).
3. **Estado do PC em 2026-10-06**: o celular já tem o PWA instalado na origem de produção (`https://desktop-arthur.tail301d2c.ts.net`, porta 443). Ele foi servido por um backend temporário do repo (porta 8000, `SERVE_FRONTEND_DIR`), e ícone, splash e "sem seleção ao segurar" foram conferidos assim. O `tailscale serve` da 443 → `127.0.0.1:8000` pode ter ficado configurado. O instalador assume a 443 (confira com `tailscale serve status`). A conferência do critério de pronto continua sendo pelo instalador.

## Escopo
- **Instalador com Inno Setup 6**, gerado no CI (`release.yml`, job em `windows-latest`) e anexado à GitHub Release como `Stemma-Setup-vX.Y.Z.exe` + `.sha256`. Sem assinatura de código (aviso do SmartScreen documentado).
- **Ferramentas portáteis com SHA256 fixado** em `C:\stemma\tools` (sem winget, que instala no perfil do usuário e não é determinístico): uv, FFmpeg e Deno. Python 3.12 via `uv python install` com `UV_PYTHON_INSTALL_DIR` em `tools\python`. O cache do uv vai para `C:\stemma\cache\uv`, no mesmo volume dos venvs, para o hardlink funcionar.
- **Reaproveitar o torch já baixado (evitar ~3 GB de novo)**:
  - **Cache fixo**: `UV_CACHE_DIR=C:\stemma\cache\uv` em todo uso do uv (instalador, `update.ps1`, tarefa da F5c). Tudo que roda como sistema usa o mesmo cache, e o torch só é baixado de novo quando a versão dele mudar no `uv.lock`.
  - **Semear na primeira instalação**: o instalador roda elevado, mas no perfil do usuário, então acha o cache dele com `uv cache dir`, rodado como o usuário (no PC atual, `%LOCALAPPDATA%\uv\cache`). No mesmo volume, cria **hardlinks** dos arquivos para `C:\stemma\cache\uv`: segundos e sem espaço extra, e um `uv cache clean` do usuário não afeta. Em outro volume, faz uma cópia comum.
  - **Detecção sem depender do formato interno do cache**: tenta `uv sync --frozen --offline`. Se falhar, roda o `uv sync` normal, que baixa só o que falta. O progresso diz qual caso foi ("Componentes encontrados no PC" / "Baixando ~3 GB").
  - **uv em `tools\` na mesma versão do uv do usuário**, quando possível: com formatos de cache diferentes, a semeadura não ajuda e o passo anterior cai no download (mais lento, nunca quebra).
- **Tailscale**: se não estiver instalado, baixa e instala o MSI oficial (silencioso). Se não estiver logado, roda `tailscale up` (abre o navegador) e espera o login. Confere se o tailnet tem HTTPS (cert domains no `tailscale status --json`); se não tiver, mostra o passo no painel e espera. Depois roda `tailscale serve --bg --https=443 http://127.0.0.1:<porta>`.
- **Telas do assistente (PT-BR)**: boas-vindas → pasta de dados (padrão `D:\stemma-data`) e porta (padrão 8000) → Tailscale (estado e login) → progresso (etapas com texto: "Baixando componentes (~3 GB na primeira vez)…") → concluído, com o endereço `https://<pc>.<tailnet>.ts.net`, um **QR code** para abrir no celular e o botão "Abrir o Stemma".
- **Instalação nova e atualização no mesmo `.exe`**: detecta a instalação existente e roda o fluxo do `update.ps1` (backup, migrations, junction, `/health`, rollback automático). Sem a tela de pasta e porta na atualização.
- **Serviço WinSW como LocalSystem** (sem `install /p`). O `start.ps1` põe `C:\stemma\tools` (e o Python/Deno de lá) no `PATH`. O `.env` ganha `FFMPEG_BIN` absoluto.
- **Desinstalador** ("Adicionar ou remover programas"): para e remove o serviço, desliga o `tailscale serve` da 443 e remove `C:\stemma`. Pergunta antes de apagar a pasta de dados (padrão: manter).
- Os scripts da F5 continuam como "motor" e para diagnóstico (`update.ps1 -Rollback`, `-YtDlpOnly`). O instalador chama as funções do módulo; nada de lógica duplicada no `.iss`.
- Testes: Pester das funções novas (download e verificação de ferramentas, detecção do Tailscale e do HTTPS, `.env` com caminhos absolutos); build do instalador no CI (`iscc`) a cada PR que toque `deploy/` ou `installer/`.
- Docs: `docs/operacao.md` reescrito para o instalador (scripts viram apêndice), ADR nova (conta do sistema + ferramentas em `tools\`), atualização da ADR 0007 (instalador no release), CLAUDE.md.

## Fora do escopo
- Botão "Atualizar" no app e aviso de versão nova do servidor ([F5c](F5c-atualizar-pelo-app.md)).
- Assinatura de código.
- Instalar o driver NVIDIA (pré-requisito: o instalador só confere com `nvidia-smi` e avisa).

## Checklist
- [x] CUDA funciona como LocalSystem (verificado antes de tudo: `2.7.1+cu118 True GTX 1650` numa tarefa como SYSTEM)
- [x] ferramentas portáteis com SHA256 em `C:\stemma\tools`
- [x] cache do uv fixo em `C:\stemma\cache\uv`, semeado do cache do usuário (hardlink), com `--offline` primeiro: instalar no PC atual não baixa o torch de novo (ensaio: 226 mil arquivos ligados em ~2,5 min; venv em 7 s)
- [x] Tailscale: instalar, login, checagem de HTTPS e `serve` (ensaio: tela "pronto" e 443 → ensaio; os ramos "não instalado", "sem login" e "sem HTTPS" só pelo Pester do parser, porque o PC já tinha o Tailscale logado)
- [x] assistente Inno Setup em PT-BR com QR code no fim
- [x] mesma `.exe` instala e atualiza (backup, migrations, rollback)
- [x] desinstalador
- [x] ícone na bandeja (`Stemma.exe`) e QR no app do desktop (pedidos na sessão)
- [ ] instalador gerado e anexado pelo `release.yml` (confere na primeira release depois do merge)
- [x] docs/operacao.md, ADR nova, ADR 0007 e CLAUDE.md

## Critério de pronto
No PC (sem nada do Stemma instalado): baixar `Stemma-Setup-vX.Y.Z.exe` da GitHub Release, instalar pelo assistente (**sem baixar o torch de novo**, porque ele já está no cache do usuário) e abrir o endereço do QR code no celular. Publicar a release seguinte e rodar o instalador novo: o `/health` mostra a versão nova sem passo manual. Simular falha na atualização e ver o rollback (`-SimulateFailure` exposto como parâmetro de linha de comando do instalador, só para teste). App instalado na tela inicial do celular com ícone e splash corretos e sem seleção de texto ao segurar. CI verde.

## Handoff
_Preencher ao final._
