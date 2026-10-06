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

## Escopo
- **Instalador com Inno Setup 6**, gerado no CI (`release.yml`, job em `windows-latest`) e anexado à GitHub Release como `Stemma-Setup-vX.Y.Z.exe` + `.sha256`. Sem assinatura de código (aviso do SmartScreen documentado).
- **Ferramentas portáteis com SHA256 fixado** em `C:\stemma\tools` (sem winget, que instala no perfil do usuário e não é determinístico): uv, FFmpeg e Deno. Python 3.12 via `uv python install` com `UV_PYTHON_INSTALL_DIR` em `tools\python`. O cache do uv vai para `C:\stemma\cache\uv`, no mesmo volume dos venvs, para o hardlink funcionar.
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
- [ ] CUDA funciona como LocalSystem (verificado antes de tudo)
- [ ] ferramentas portáteis com SHA256 em `C:\stemma\tools`
- [ ] Tailscale: instalar, login, checagem de HTTPS e `serve`
- [ ] assistente Inno Setup em PT-BR com QR code no fim
- [ ] mesma `.exe` instala e atualiza (backup, migrations, rollback)
- [ ] desinstalador
- [ ] instalador gerado e anexado pelo `release.yml`
- [ ] docs/operacao.md, ADR nova, ADR 0007 e CLAUDE.md

## Critério de pronto
No PC (sem nada do Stemma instalado): baixar `Stemma-Setup-vX.Y.Z.exe` da GitHub Release, instalar pelo assistente e abrir o endereço do QR code no celular. Publicar a release seguinte e rodar o instalador novo: o `/health` mostra a versão nova sem passo manual. Simular falha na atualização e ver o rollback (`-SimulateFailure` exposto como parâmetro de linha de comando do instalador, só para teste). App instalado na tela inicial do celular com ícone e splash corretos e sem seleção de texto ao segurar. CI verde.

## Handoff
_Preencher ao final._
