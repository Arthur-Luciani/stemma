# Operação — Stemma no PC

Como instalar, atualizar, parar, voltar versão e conferir o Stemma rodando como serviço do Windows ([ADR 0002](decisions/0002-runtime-nativo-windows.md), [ADR 0007](decisions/0007-processo-de-release.md), [ADR 0014](decisions/0014-instalador-e-conta-do-sistema.md)).

## Instalar

1. Baixe `Stemma-Setup-vX.Y.Z.exe` da [GitHub Release](https://github.com/Arthur-Luciani/stemma/releases/latest).
2. Abra. O Windows avisa "O Windows protegeu o computador" (o instalador não tem assinatura de código): **Mais informações → Executar assim mesmo**. Aceite o pedido de administrador.
3. O assistente pergunta:
   - **pasta de dados** (padrão `D:\stemma-data`): músicas, stems, exportações e banco;
   - **porta** local (padrão 8000);
   - **Tailscale**: se não estiver instalado, o botão instala; se não estiver logado, **Entrar** abre o login no navegador; se o tailnet não tiver HTTPS, **Abrir o painel** leva a DNS → *HTTPS Certificates* (ative e clique em **Verificar de novo**).
4. Progresso: ferramentas (uv, FFmpeg, Deno, Python), reaproveitamento do cache do uv do PC, ambiente da versão, banco, serviço, `tailscale serve`.
5. No fim: o endereço `https://<pc>.<tailnet>.ts.net`, um **QR code** para abrir no celular e o botão **Abrir o Stemma**.

Pré-requisito que o instalador só confere: driver da NVIDIA (`nvidia-smi`). Sem ele, a separação roda na CPU (bem mais lenta).

**Torch (~3 GB):** na primeira instalação o instalador liga por hardlink o cache do uv do seu usuário (`uv cache dir`) em `C:\stemma\cache\uv` e tenta montar o ambiente só com ele (`uv sync --offline`). Se faltar algo, baixa só o que falta. O log diz qual caso foi ("Componentes encontrados no PC" ou "Baixando componentes").

## Atualizar

Baixe e rode o `Stemma-Setup-vX.Y.Z.exe` da versão nova. Ele detecta a instalação e vai direto ao progresso:

download conferido (já vem dentro do `.exe`) → ambiente da versão nova (com o serviço ainda no ar) → para o serviço → **backup do banco** em `<dados>\backups\` → migrations → `current` aponta para a nova → sobe → espera o `/health` responder com a versão nova (até 3 min). Ficam as 3 versões mais novas.

**Se algo falhar depois de parar o serviço**, o instalador restaura o banco do backup, volta o `current`, sobe a versão anterior e mostra "Não deu certo… A versão anterior continua no ar".

Para testar o rollback: `Stemma-Setup-vX.Y.Z.exe /SIMULATEFAILURE` (a checagem do `/health` falha de propósito).

No celular, o app avisa "Nova versão disponível" com o botão **Recarregar**.

## Ícone na bandeja, parar e iniciar

O Stemma fica sempre no ar, como o Tailscale: um **serviço do Windows** sobe com o Windows (início automático atrasado, mesmo sem login) e reinicia sozinho se cair (10 s, 30 s, depois a cada 60 s). Ocioso, usa ~250 MB de RAM e nada de CPU/GPU; a GPU só trabalha durante uma separação.

O **ícone do Stemma perto do relógio** (`C:\stemma\setup\Stemma.exe`, abre no login) mostra o estado (ícone colorido = no ar; cinza = parado ou iniciando) e tem:

- **clique**: abre o Stemma no navegador;
- **Abrir no celular…**: o QR code do endereço do Tailscale;
- **Parar o Stemma**: para o serviço e deixa a inicialização **manual** (não volta quando o Windows reiniciar). Pede administrador;
- **Iniciar o Stemma**: volta ao início automático, sobe e confere o `/health`. Pede administrador;
- **Sair**: fecha só o ícone (o Stemma continua no ar). Para trazer de volta: Menu Iniciar → **Stemma**.

No Menu Iniciar, **Stemma** abre o navegador (e põe o ícone na bandeja, se não estiver). No app, no desktop, o botão de QR no canto da barra do topo mostra o mesmo QR.

Equivalente em linha de comando (administrador): `Stop-Service stemma`, `Start-Service stemma`, `services.msc`.

## Desinstalar

**Configurações → Aplicativos → Stemma → Desinstalar.** Para e remove o serviço, desliga o `tailscale serve` da 443, remove os atalhos e apaga `C:\stemma` (ferramentas, versões, cache, logs). Pergunta se apaga também a pasta de dados (padrão: **não**). O Tailscale continua instalado.

## Layout

```
C:\stemma\
  .env                  configuração de produção (PORT, STORAGE_ROOT, FFMPEG_BIN…; ver .env.example)
  install.json          serviço e se o instalador ligou o tailscale serve (usado no update e no desinstalador)
  current\              junction → releases\vX.Y.Z (a versão no ar)
  releases\vX.Y.Z\      uma pasta por versão, cada uma com o próprio venv (backend\.venv)
  tools\                uv, ffmpeg\bin, deno e python\ (versões e SHA256 fixados no StemmaDeploy.psm1)
  cache\uv\             cache do uv (no mesmo volume dos venvs, para o hardlink)
  setup\                Stemma.exe (ícone da bandeja), desinstalador, motor (engine\setup.ps1 + StemmaDeploy.psm1), pacote, QR
  winsw\                stemma.exe (WinSW 2.12) + stemma.xml
  logs\                 serviço (stemma.out.log / stemma.err.log, rotação) e setup-*.log do instalador
D:\stemma-data\         STORAGE_ROOT: banco, stems, exports, cache do torch
  backups\              backups do banco feitos antes de cada atualização
```

- O serviço `stemma` roda como **LocalSystem** (não pede senha) e executa `current\deploy\start.ps1`: põe `tools\` no `PATH`, carrega o `.env`, aplica as migrations e sobe o uvicorn (1 worker) em `127.0.0.1:<porta>`, servindo também o `frontend\dist` da versão.
- Acesso de fora só pelo `tailscale serve`: `https://<pc>.<tailnet>.ts.net` → `http://127.0.0.1:<porta>`.

## Voltar versão (rollback manual)

```powershell
powershell -ExecutionPolicy Bypass -File C:\stemma\current\deploy\update.ps1 -Rollback
```

Volta para a versão instalada imediatamente anterior. Faz backup do banco, desfaz as migrations até o head daquela versão (`alembic downgrade`), troca o `current` e sobe. Os dados novos continuam no banco; só o schema volta.

## Só o yt-dlp

Quando o YouTube quebra o download e já saiu um yt-dlp novo:

```powershell
powershell -ExecutionPolicy Bypass -File C:\stemma\current\deploy\update.ps1 -YtDlpOnly
```

Atualiza o yt-dlp no venv da versão atual e reinicia o serviço. O `/health` mostra a versão (`ytdlp`). A próxima atualização volta para a versão do `uv.lock`.

## Cookies do YouTube

Se o download falhar com "YouTube pediu login. Atualize os cookies.":

1. Exporte os cookies do youtube.com no formato Netscape (extensão "Get cookies.txt LOCALLY", logado numa conta).
2. Salve em `D:\stemma-data\cookies.txt`.
3. No `C:\stemma\.env`: `YTDLP_COOKIE_FILE=D:\stemma-data\cookies.txt`.
4. Reinicie: ícone da bandeja → Parar o Stemma e depois Iniciar o Stemma (ou `Restart-Service stemma`).

## Logs e diagnóstico

```powershell
Get-Content C:\stemma\logs\stemma.err.log -Tail 50 -Wait   # o log do app vai para o stderr
Get-ChildItem C:\stemma\logs\setup-*.log                   # cada execução do instalador
Get-Service stemma
Invoke-RestMethod http://127.0.0.1:8000/health
tailscale serve status
```

## App no celular (PWA)

1. Escaneie o QR code do fim da instalação, ou abra `https://<pc>.<tailnet>.ts.net` no Chrome do Android (sem `:5183`, que é o Vite do dev).
2. Menu ⋮ → **Instalar app**.
3. Se você tinha instalado o atalho antigo (do `:5183`), remova-o: é outra origem e não atualiza.

Instalado, o app abre em tela cheia, com splash escura e o ícone da marca. Segurar não seleciona texto nem abre menu, e não há zoom com dois dedos (campos de texto continuam normais). O service worker guarda só o app (HTML, JS, CSS, ícones). Áudio, stems, exports e API sempre vêm do PC.

## Smoke manual pós-update

O CI não tem GPU. Depois de cada update:

- [ ] `Invoke-RestMethod http://127.0.0.1:8000/health`: `version` nova, `status: ok`, `gpu: ok`, `db: ok`.
- [ ] Desktop: abrir `https://<pc>.<tailnet>.ts.net`, a Biblioteca carrega.
- [ ] Processar uma faixa curta (busca → Separar) até "Pronta".
- [ ] Celular (app instalado): aparece "Nova versão disponível" → Recarregar; abrir o mixer, tocar, mutar um stem.
- [ ] Exportar MP3 e baixar no celular.
- [ ] `Get-Content C:\stemma\logs\stemma.err.log -Tail 30` sem `ERROR`.

## Apêndice: scripts (sem o instalador)

O instalador é uma casca sobre `deploy\StemmaDeploy.psm1`. Os mesmos fluxos existem como scripts, para diagnóstico e ensaio (PowerShell **como administrador**):

| Script | Para quê |
|---|---|
| `deploy\install.ps1` | instalação nova sem telas (`-ZipPath`, `-Version`, `-Root`, `-DataRoot`, `-Port`, `-ServiceId`, `-SkipTailscale`) |
| `deploy\update.ps1` | atualizar (`-Version`, `-ZipPath`, `-SimulateFailure`), `-Rollback`, `-YtDlpOnly` |
| `deploy\setup.ps1` | motor do instalador (`-Mode Check/Install/Update/Uninstall/Start/Stop/…`) |
| `installer\build.ps1` | compila o `.exe` a partir de um `stemma-vX.Y.Z.zip` (precisa do Inno Setup 6.3+) |
| `scripts/package.sh` | monta o `stemma-vX.Y.Z.zip` (precisa do `frontend/dist`) |

**Ensaio numa instalação paralela** (não mexe no `C:\stemma` nem na 443):

```powershell
Stemma-Setup-vX.Y.Z.exe /ROOT=C:\stemma-ensaio /SERVICEID=stemma-ensaio /PORT=8001 /DATAROOT=D:\stemma-ensaio-data /SKIPTAILSCALE
```

Aparece como "Stemma (stemma-ensaio)" no Menu Iniciar e em Aplicativos, separado da instalação real.
