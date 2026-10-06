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
**Status:** implementação no PR da F5b. O **ensaio local** passou por inteiro, com instaladores compilados aqui numa instalação paralela (`C:\stemma-ensaio`, porta 8001). Fica pendente o **critério de pronto real**: instalar pelo `.exe` da GitHub Release e atualizar para a release seguinte. Isso só pode ser feito depois do merge e da release.

### Feito
- **Pré-checagem**: o torch enxerga a GPU como SYSTEM (`2.7.1+cu118 True GTX 1650`, tarefa agendada temporária).
- **Instalador** (`installer/stemma.iss`, Inno Setup 6.3+, PT-BR):
  - telas: boas-vindas, pasta de dados, porta, Tailscale (instalar / Entrar / painel de HTTPS / Verificar de novo), progresso por etapa e tela final com endereço, QR e "Abrir o Stemma";
  - o mesmo `.exe` instala e atualiza;
  - `/SIMULATEFAILURE` para testar o rollback;
  - `/ROOT /SERVICEID /PORT /DATAROOT /SKIPTAILSCALE` para ensaio paralelo;
  - desinstalador com a pergunta sobre os dados (padrão: manter).
- **Motor** `deploy/setup.ps1` (Check, Install, Update, Uninstall, Start, Stop, TailscaleInstall, TailscaleLogin). A lógica foi para o `StemmaDeploy.psm1`:
  - `Invoke-StemmaInstall`, `Invoke-StemmaUpdate`, `Invoke-StemmaRollback`, `Invoke-StemmaUninstall`, `Update-StemmaYtDlp`;
  - o `install.ps1` e o `update.ps1` viraram cascas.
- **Ferramentas** em `<raiz>\tools`: uv 0.12.7, FFmpeg 9.0.2 e Deno 2.9.7, com SHA256 fixado, mais Python 3.12 via `uv python install --no-bin --no-registry`. O serviço roda como **LocalSystem**.
- **Cache do uv** em `<raiz>\cache\uv`:
  - semeado por hardlink a partir do cache do usuário;
  - o `uv sync --offline` é tentado primeiro;
  - ensaio: 226 mil arquivos em ~2,5 min, venv em 7 s, torch não baixado de novo.
- **Pastas protegidas** (achado do `/code-review`):
  - `<raiz>` e os dados ficam só com SYSTEM e Administradores alterando, e Administradores como dono;
  - consequência: os arquivos do cache do uv do usuário ligados por hardlink ficam só leitura para ele (ADR 0014).
- **Tailscale**:
  - checagem por `tailscale status --json`, instalação por MSI fixo e login pelo navegador;
  - `serve` 443 → porta, refeito na atualização;
  - o desinstalador só desliga o `serve` se foi o instalador que ligou (`install.json`).
- **Bandeja** (pedido na sessão: "parecer um app, como o Tailscale"):
  - `Stemma.exe` (`installer/tray`, C# 5 compilado no build), com DPI por monitor e tema escuro dos tokens;
  - mostra o estado e oferece Abrir, QR, Parar (manual), Iniciar (automático) e Sair;
  - abre no login e no fim da instalação; no Menu Iniciar fica só "Stemma".
- **App** (pedido na sessão):
  - botão discreto de QR na topbar do desktop (`OpenOnPhone`, `uqr`), que explica em vez de mostrar QR quando o endereço é `localhost`;
  - a mensagem de rede agora aponta para o Tailscale do aparelho.
- **Ícone** `installer/stemma.ico` em 8 tamanhos, gerado do SVG pelo `npm run gen:icons`.
- **CI**:
  - job `installer` (`windows-latest`): Pester no Windows PowerShell 5.1 e build do instalador quando `deploy/`, `installer/`, o empacotamento ou os workflows mudam;
  - saiu o Pester do Linux;
  - `release.yml` anexa `Stemma-Setup-vX.Y.Z.exe` + `.sha256`;
  - empacotamento em `scripts/package.sh`.
- **Testes**: Pester 31 → 70.
- **Ensaio local** (com você clicando no assistente): instalação nova; atualização com falha simulada (rollback com banco restaurado); atualização normal; desinstalação (dados mantidos); reinstalação reaproveitando o banco; Tailscale de verdade (443 → ensaio) e QR; bandeja.
- **`/code-review`**: 10 achados, todos corrigidos:
  - bytes de controle nos workflows (`\b`): agora há um teste que procura isso;
  - pastas graváveis por usuários comuns executadas como SYSTEM;
  - reinstalação depois de falha caía em "já está na versão" sem conferir nada;
  - FFmpeg e Deno trocados com o serviço no ar;
  - a atualização não semeava o cache;
  - exceção no seeder;
  - `tailscale serve` sem Tailscale;
  - caminho com `\` no fim e a raiz de um drive como pasta de dados;
  - exceções no timer da bandeja;
  - marcador vazio.

### Pendente
- **Critério de pronto real** (depois do merge e da release v1.4.0):
  1. **Remover o ensaio**: Configurações → Aplicativos → "Stemma (stemma-ensaio)" → Desinstalar, apagando também `D:\stemma-ensaio-data`. Isso libera a 443.
  2. Baixar `Stemma-Setup-v1.4.0.exe` da Release e instalar em `C:\stemma`. Conferir "Componentes encontrados no PC" no log, QR no celular e PWA.
  3. Um `fix:` gera a v1.4.1: rodar o instalador novo com `/SIMULATEFAILURE` (volta para a 1.4.0) e depois normal (`/health` 1.4.1).
- Medir quanto a proteção das pastas acrescenta à primeira instalação: o `icacls` percorre ~230 mil arquivos do cache.
- Ramos do Tailscale "não instalado", "sem login" e "sem HTTPS": validados só pelo Pester do parser. O PC já tinha o Tailscale logado.
- Herdados: medição do AudioEngine no Android (F4a), branch protection (F0), iPhone (F5).

### Decisões
- [ADR 0014](../decisions/0014-instalador-e-conta-do-sistema.md): instalador, LocalSystem, `tools\`, cache semeado, pastas protegidas, serviço + bandeja.
- Notas nas ADRs [0002](../decisions/0002-runtime-nativo-windows.md) e [0007](../decisions/0007-processo-de-release.md).
- Cache do usuário em outro volume: **sem** semear (o plano previa copiar, mas copiar dezenas de GB sai mais caro que baixar ~3 GB).
- Desvios de design (QR na topbar, QR escuro sobre claro, bandeja fora dos tokens CSS) em [docs/design](../design/README.md#desvios).

### Pegadinhas
- **"untrusted mount point"**: um processo elevado não atravessa junctions criadas pelo usuário. O cache antigo do uv (`wheels-v3`) tem junctions, e o seeder as pula.
- **`uv python install` sem `--no-bin --no-registry`** escreve no perfil do usuário (`~\.local\bin`, `HKCU\Software\Python\Astral`). Aconteceu no primeiro ensaio; a chave foi apagada à mão.
- **`icacls ... /T` com `(OI)(CI)` aplicado a arquivos deixa o arquivo sem nenhuma permissão.** O certo é: proteger a pasta (sem `/T`), depois `pasta\* /reset /T`, depois `/setowner /T`.
- **Python escrevendo arquivos com `\b`/`\t` dentro de strings normais** gerou bytes de controle em workflow e script. O Pester agora acusa.
- **`[IO.Path]::GetFullPath('D:')`** devolve o diretório atual do drive D, e não `D:\`. Aqui passava por acaso; no runner (checkout em `D:\a\…`) não. Trate `X:` à parte.
- **`"$var:"` no PowerShell** é variável com escopo (`$var:texto`). Use `"$($var):"`.
- **Inno**: uma linha do `[Code]` que começa com `#` (ex.: `#13#10`) é lida como diretiva do pré-processador. `AppId` com `{code:}` exige `UsePreviousLanguage=no`.
- **O `!` do Claude Code roda no bash**: para rodar `.exe` com parâmetros `/X=...`, use um `.ps1` (o Git Bash converte `/ROOT` em caminho).
- **O PWA já instalado no celular abre mesmo com o Tailscale do celular desligado** (o service worker serve a casca), e então dá erro de conexão. Confira `tailscale status`: o celular aparece `offline`.
- **WinForms sem manifesto de DPI** fica borrado com escala acima de 100%: use `Stemma.manifest` (`PerMonitorV2`) no `csc /win32manifest`.
- O ícone `.ico` com só 16/32/192 px fica feio na bandeja a 125%: gere todos os tamanhos (`gen:icons`).
