# 0014 — Instalador `.exe`, serviço como LocalSystem e ferramentas em `tools\`

- **Status:** aceita (2026-10-06, F5b)
- Muda a [ADR 0002](0002-runtime-nativo-windows.md) (conta do serviço e pré-requisitos) e complementa a [ADR 0007](0007-processo-de-release.md) (o que a release publica).

## Contexto
Na F5, instalar era rodar `install.ps1` num PowerShell de administrador, com uv, FFmpeg e Deno instalados à mão no PATH do usuário, o WinSW pedindo conta e senha do Windows (`install /p`) e o `tailscale serve` configurado à mão. O usuário achou difícil e pediu um instalador. Rodar o serviço com a conta do usuário também amarrava tudo ao perfil dele (PATH, cache do uv, Python do `%APPDATA%`).

## Decisão
- **Instalador Inno Setup 6.3+** (`installer/stemma.iss`), gerado pelo `release.yml` (job `installer`, `windows-latest`) e anexado à GitHub Release como `Stemma-Setup-vX.Y.Z.exe` + `.sha256`. Ele carrega dentro o `stemma-vX.Y.Z.zip` da própria release. Sem assinatura de código: o aviso do SmartScreen é aceito e documentado.
- **O mesmo `.exe` instala e atualiza.** Se `<raiz>\current` e o serviço existem, roda o fluxo de atualização da ADR 0007 (backup, migrations, `/health`, rollback automático). `/SIMULATEFAILURE` testa o rollback.
- **O `.iss` não tem lógica.** Ele só monta as telas e chama `deploy\setup.ps1` (o motor), que usa as funções do `deploy\StemmaDeploy.psm1`. São as mesmas funções do `install.ps1`, do `update.ps1` e, na F5c, da tarefa agendada. O motor fala com o instalador pela saída padrão: `==> etapa`, `##RESULT k=v`, `##ERROR msg`. O Inno lê essa saída com `ExecAndLogOutput`.
- **Serviço como LocalSystem** (WinSW sem `<serviceaccount>`): a instalação não pede senha. Verificado antes de tudo: o torch enxerga a GPU como SYSTEM (`torch.cuda.is_available() == True`).
- **Ferramentas portáteis em `<raiz>\tools`**: uv, FFmpeg (gyan.dev essentials) e Deno, com versão e SHA256 fixados no módulo. Python 3.12 via `uv python install --no-bin --no-registry` em `tools\python`. Nada vai para o perfil do usuário (nem `~\.local\bin` nem `HKCU\Software\Python`). O `start.ps1` põe `tools\` no `PATH` do serviço, e o `.env` ganha `FFMPEG_BIN` absoluto. Sem winget: ele instala no perfil do usuário e não é determinístico.
- **Cache do uv fixo em `<raiz>\cache\uv`** (`UV_CACHE_DIR`), no mesmo volume dos venvs. Na primeira instalação é **semeado por hardlink** a partir do cache do usuário (`uv cache dir`, rodado antes de trocar o ambiente). Depois, o `uv sync --frozen --offline` é tentado primeiro e só baixa se faltar algo. No PC de referência: 226 mil arquivos (17 GB) ligados em ~2,5 min, sem espaço extra, e o torch não foi baixado de novo.
  - Junctions do cache (formato antigo, `wheels-v3`) não são atravessadas: um processo elevado recusa junctions criadas pelo usuário ("untrusted mount point").
  - Se o cache do usuário estiver em **outro volume**, não há semeadura (desvio do plano, que previa copiar). Copiar o cache inteiro (dezenas de GB) sai mais caro que baixar os ~3 GB que faltam.
- **Tailscale pelo instalador**: instala o MSI oficial (versão e SHA256 fixados) se faltar, abre o login (`tailscale up`, URL de autenticação no navegador), confere o HTTPS do tailnet (`CertDomains` do `tailscale status --json`) e roda `tailscale serve --bg --https=443 http://127.0.0.1:<porta>`. O `install.json` registra se foi o instalador que ligou o serve, para o desinstalador só desligar o que ligou.
- **Serviço + ícone na bandeja**, como o Tailscale (decisão do usuário: o Stemma tinha que parecer um app, e não só um serviço invisível). `Stemma.exe` (`installer/tray`, C# 5 compilado no build com o `csc` do .NET Framework 4, que vem em todo Windows, com manifesto de DPI por monitor e o tema escuro dos tokens) abre no login e no fim da instalação. Ele mostra o estado (serviço + `/health`) e tem: abrir no navegador (clique), QR para o celular, Parar (para e deixa a inicialização manual), Iniciar (volta ao automático atrasado e confere o `/health`) e Sair (fecha só o ícone). Parar e Iniciar chamam o motor, que pede UAC sozinho. No Menu Iniciar fica só **Stemma** (abre o navegador e o ícone). Descartado: um app de bandeja **sem** serviço (como o Spotify), porque só funcionaria com o usuário logado, voltaria à conta do usuário e complicaria a atualização pelo app (F5c).
- **QR no próprio app**: no desktop, um botão discreto na topbar mostra o QR do endereço atual (`uqr`, em SVG). Em `localhost`, mostra uma explicação no lugar do QR.
- **Desinstalador**: remove o serviço, o `tailscale serve` da 443 (se foi o instalador que ligou), os atalhos e `<raiz>`. A pasta de dados só é apagada se o usuário confirmar (padrão: manter).
- **CI**: o Pester passa a rodar no Windows PowerShell 5.1 (job `installer`, só quando `deploy/`, `installer/`, `scripts/package.sh` ou os workflows mudam), que também compila o instalador com um pacote de teste. O job Pester no pwsh do Linux saiu: junction, hardlink e serviço só existem no Windows. O empacotamento foi para `scripts/package.sh` (usado pelo CI e pelo `release.yml`).

## Alternativas descartadas
- **Conta do usuário** (como na F5): exige a senha no instalador e prende ferramentas e cache ao perfil.
- **Conta virtual `NT SERVICE\stemma`**: não foi necessária, já que a GPU funciona como SYSTEM. Ainda exigiria ajustar ACLs de `D:\stemma-data` e de `tools\`.
- **WiX/MSI**: mais cerimônia para um app de um usuário só; o Inno faz as telas customizadas (Tailscale, QR) com pouco código.
- **Embutir as ferramentas no `.exe`**: ~250 MB a mais em toda versão; baixar com SHA256 fixado dá o mesmo determinismo.

## Consequências
- O Stemma roda com privilégios de sistema. Isso é aceitável num PC pessoal, com o uvicorn escutando só em `127.0.0.1` e o acesso de fora só pelo Tailscale.
- Trocar a versão de uma ferramenta = trocar versão + SHA256 no `StemmaDeploy.psm1` (o `Install-StemmaTool` reinstala quando a marca `.stemma-tool` não bate).
- O `.exe` precisa de Inno Setup ≥ 6.3 (`ExecAndLogOutput`/`ExecAndCaptureOutput`).
- Ensaio sem tocar na instalação real: `/ROOT=… /SERVICEID=… /PORT=… /DATAROOT=… /SKIPTAILSCALE` (outro `AppId`, outra pasta no Menu Iniciar).
