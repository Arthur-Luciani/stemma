# Operação — Stemma no PC

Como instalar, atualizar, parar, voltar versão e conferir o Stemma rodando como serviço do Windows ([ADR 0002](decisions/0002-runtime-nativo-windows.md), [ADR 0007](decisions/0007-processo-de-release.md), [ADR 0014](decisions/0014-instalador-e-conta-do-sistema.md)).

## Instalar

1. Baixe `Stemma-Setup-vX.Y.Z.exe` da [GitHub Release](https://github.com/Arthur-Luciani/stemma/releases/latest).
2. Abra. O Windows avisa "O Windows protegeu o computador" (o instalador não tem assinatura de código): **Mais informações → Executar assim mesmo**. Aceite o pedido de administrador.
3. O assistente pergunta só a **pasta de dados** (padrão `D:\stemma-data`): músicas, stems, exportações e banco. O resto é automático:
   - **porta local**: a primeira livre a partir da 8000 (ver [Portas](#portas); `/PORT=` força outra);
   - **endereço HTTPS**: `https://<pc>.<tailnet>.ts.net` (443) ou, se esse endereço já for de outro app do PC, `:8443`, sem mexer no outro app;
   - **Tailscale**: a tela só aparece quando há o que fazer. Se não estiver instalado, o botão instala; se não estiver logado, **Entrar** abre o login no navegador; se o tailnet não tiver HTTPS, **Abrir o painel** leva a DNS → *HTTPS Certificates* (ative e clique em **Verificar de novo**).
4. **Pronto para instalar**: o endereço, quanto vai baixar (quase nada se o torch já estiver no cache do uv do PC; ~3 GB se não estiver) e o espaço em disco necessário e livre. Sem espaço no drive de `C:\stemma`, não começa.
5. Progresso em etapas numeradas ("Etapa 6 de 9: Reaproveitando os componentes deste PC"), com barra de percentual: conferir o PC, proteger as pastas, extrair, ferramentas (uv, FFmpeg, Deno), Python, reaproveitar o cache do uv, componentes, banco e serviço (com o `tailscale serve`).
6. No fim: o endereço, um **QR code** para abrir no celular e o botão **Abrir o Stemma**.

Tempos no PC de referência (2026-10-06): **~1 min** com o torch já no cache do uv do PC (antes: ~8 min); atualização em ~20 s.

**Espaço:** ferramentas + Python ~0,5 GB; componentes ~5,5 GB descompactados (~3 GB de download) se não estiverem no PC; cada música ~50 MB (de 40 a 100 MB), mais 80 MB do modelo de separação, uma vez.

Pré-requisito que o instalador só confere: driver da NVIDIA (`nvidia-smi`). Sem ele, a separação roda na CPU (bem mais lenta).

**Torch (~3 GB):** na primeira instalação, o instalador liga por hardlink, do cache do uv do seu usuário (`uv cache dir`) para `C:\stemma\cache\uv`, **só os pacotes que o `uv.lock` da versão usa**, mais o build backend (`hatchling`, com as dependências dele e o `editables`). Cada arquivo ligado ganha uma ACL protegida: só administradores alteram, inclusive no seu cache, porque é o mesmo arquivo. Depois o instalador tenta montar o ambiente só com isso (`uv sync --offline`); se faltar algo, baixa só o que falta. O log diz qual caso foi ("Componentes encontrados no PC" ou "Baixando o que falta").

## Atualizar

Baixe e rode o `Stemma-Setup-vX.Y.Z.exe` da versão nova. Ele detecta a instalação, mostra a tela **Pronto para instalar** (versão atual → nova, download e espaço) com o botão **Atualizar** e segue em etapas numeradas:

download conferido (já vem dentro do `.exe`) → ambiente da versão nova (com o serviço ainda no ar) → para o serviço → **backup do banco** em `<dados>\backups\` → migrations → `current` aponta para a nova → sobe → espera o `/health` responder com a versão nova (até 3 min). Ficam as 3 versões mais novas.

**Se algo falhar depois de parar o serviço**, o instalador restaura o banco do backup, volta o `current`, sobe a versão anterior e mostra "Não deu certo… A versão anterior continua no ar".

Para testar o rollback: `Stemma-Setup-vX.Y.Z.exe /SIMULATEFAILURE` (a checagem do `/health` falha de propósito).

No celular, o app avisa "Nova versão disponível" com o botão **Recarregar**.

### Atualizar pelo app (sem ir ao PC)

Quando sai uma release nova (com o instalador já anexado), o app mostra **"vX.Y.Z disponível"**: um chip na topbar do desktop ou uma faixa no topo do Descobrir e da Biblioteca no celular. **Ver** abre a versão atual → nova, as novidades e o botão **Atualizar** (ADR 0015):

- o backend roda a tarefa agendada `\Stemma\Atualizar` (SYSTEM), que baixa o `Stemma-Setup-vX.Y.Z.exe` da Release, confere o SHA256 e o roda em modo silencioso. É a mesma atualização de rodar o `.exe` à mão, com backup e rollback;
- o app fica fora do ar por ~1 min, mostra "Atualizando…" e volta sozinho. Depois aparece o "Recarregar" do PWA;
- se falhar, o app mostra o motivo e a versão anterior continua no ar;
- não começa com música sendo processada ou exportada (o botão fica desabilitado);
- a consulta ao GitHub tem cache de 6 h no servidor: uma release nova pode levar até 6 h para aparecer (ou reinicie o serviço);
- as tarefas (`Atualizar` e `Bandeja`, que reabre o ícone da bandeja) são criadas pelo instalador. Uma instalação anterior à F5c ganha as tarefas no próximo `.exe` rodado à mão.

Linha de comando do instalador usada pela tarefa: `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOTRAY /RESULTFILE=<arq> /LOG=<arq>`. O código de saída é 1 na falha.

Ensaio sem publicar release (como foi feito na F5c): `UPDATE_RELEASES_URL=file:///C:/…/releases.json` no `.env` (lista no formato da API do GitHub) e `-InstallerPath <exe>` (com `-SimulateFailure`, se for o caso) nos argumentos da tarefa.

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

**Configurações → Aplicativos → Stemma → Desinstalar.** Para e remove o serviço, desliga o `tailscale serve` da 443 (ou 8443) **se ela ainda publica este Stemma**, remove os atalhos e apaga `C:\stemma` (ferramentas, versões, cache, logs). Pergunta se apaga também a pasta de dados (padrão: **não**). O Tailscale continua instalado.

## Portas

Cada app escuta só em `127.0.0.1:<porta>`, e o `tailscale serve` publica em HTTPS. Para vários apps no mesmo PC:

- **Escolha portas entre 1024 e 49151.** Abaixo disso são do sistema; acima, o Windows sorteia para conexões de saída.
- **Um bloco por app, produção e dev separados**, numa tabelinha sua. Ex.: Stemma 8000 (dev 8010 + Vite 5183); próximo app 8100 (dev 8110 + 5283).
- **No Tailscale, uma porta HTTPS por app**: `https://<pc>.ts.net` (443) para um, `:8443` para outro, e assim por diante. Separar por caminho (`/app2`) costuma quebrar SPAs.
- **Portas reservadas pelo Windows** (Hyper-V, WSL, Docker) falham com "acesso negado" mesmo parecendo livres.

```powershell
Get-NetTCPConnection -State Listen | Sort-Object LocalPort | Select-Object LocalAddress, LocalPort, OwningProcess   # quem escuta
netsh int ipv4 show excludedportrange protocol=tcp                                                                 # reservadas
tailscale serve status                                                                                             # o que o Tailscale publica
```

O instalador do Stemma já aplica isso, sem perguntar nada:
- usa a primeira porta livre (nem em uso, nem reservada) a partir da 8000;
- nunca toma a 443 de outro app: nesse caso usa a 8443 (se as duas forem de outros apps, pede para liberar uma);
- só desliga a porta HTTPS na desinstalação se ela ainda aponta para ele;
- na atualização, refaz o `serve` só se ele sumiu, nunca por cima de outro app.

Para mudar a porta de uma instalação existente:
1. Edite `PORT` no `C:\stemma\.env` como administrador.
2. Veja a porta HTTPS dela em `C:\stemma\install.json` (`httpsPort`: 443 ou 8443) e rode `tailscale serve --bg --https=<httpsPort> http://127.0.0.1:<nova>`.
3. Reinicie o Stemma (ícone da bandeja → Parar e depois Iniciar).

## Espaço em disco

O Explorer ("Propriedades") soma cada caminho de um arquivo, e o Stemma usa **hardlinks**: o mesmo arquivo no disco aparece no cache do uv (`cache\uv`), no venv de cada versão (`releases\vX.Y.Z`), no `current` (junction) e no cache do uv do seu usuário. Por isso `C:\stemma` "parece" ter 20+ GB, mas ocupa de verdade ~6 GB, quase tudo torch com CUDA, que é inevitável. As 3 versões guardadas para rollback quase não custam espaço a mais enquanto usam o mesmo torch.

- O instalador e cada atualização **enxugam o cache do uv** (`Optimize-StemmaUvCache`): fica só o que os `uv.lock` das versões instaladas usam.
- Para enxugar à mão (administrador): `powershell -ExecutionPolicy Bypass -File C:\stemma\setup\engine\setup.ps1 -Mode PruneCache`.
- O cache do uv do seu usuário (`uv cache dir`) é outra coisa. Ele guarda os pacotes de todos os seus projetos de dev, e o Stemma não depende dele depois de instalado. `uv cache clean` libera o que nenhum venv usa; os venvs continuam funcionando.

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
  logs\                 serviço (stemma.out.log / stemma.err.log, rotação), setup-*.log do instalador,
                        update-vX.Y.Z.log (instalador rodado pelo app) e app-update-result.txt
  downloads\            instalador baixado pela atualização pelo app
D:\stemma-data\         STORAGE_ROOT: banco, stems, exports, cache do torch
  backups\              backups do banco feitos antes de cada atualização
```

- O serviço `stemma` roda como **LocalSystem** (não pede senha) e executa `current\deploy\start.ps1`: põe `tools\` no `PATH`, carrega o `.env`, aplica as migrations e sobe o uvicorn (1 worker) em `127.0.0.1:<porta>`, servindo também o `frontend\dist` da versão.
- Tarefas agendadas `\Stemma\Atualizar` (SYSTEM, sob demanda) e `\Stemma\Bandeja` (grupo Usuários): atualização pelo app. O `.env` aponta para a primeira em `UPDATE_TASK`.
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
2. Copie para `D:\stemma-data\cookies.txt` e, no `C:\stemma\.env`, ponha `YTDLP_COOKIE_FILE=D:\stemma-data\cookies.txt`. As duas pastas são protegidas (só administradores alteram; ADR 0014): use o Explorer e confirme o pedido de administrador, ou um editor aberto como administrador.
3. Reinicie: ícone da bandeja → Parar o Stemma e depois Iniciar o Stemma (ou `Restart-Service stemma`).

## Logs e diagnóstico

```powershell
Get-Content C:\stemma\logs\stemma.err.log -Tail 50 -Wait   # o log do app vai para o stderr
Get-ChildItem C:\stemma\logs\setup-*.log                   # cada execução do instalador
Get-Content C:\stemma\logs\app-update-result.txt          # resultado da última atualização pelo app
Get-ScheduledTask -TaskPath '\Stemma\'                    # tarefas da atualização pelo app
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
