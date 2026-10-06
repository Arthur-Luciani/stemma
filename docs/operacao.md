# Operação — Stemma no PC

Como instalar, atualizar, voltar versão e conferir o Stemma rodando como serviço do Windows ([ADR 0002](decisions/0002-runtime-nativo-windows.md), [ADR 0007](decisions/0007-processo-de-release.md)).

## Layout

```
C:\stemma\
  .env                  configuração de produção (PORT, STORAGE_ROOT, …; ver .env.example)
  current\              junction → releases\vX.Y.Z (a versão no ar)
  releases\vX.Y.Z\      uma pasta por release, cada uma com o próprio venv (backend\.venv)
  downloads\            zips baixados
  logs\                 logs do serviço (stemma.out.log / stemma.err.log, rotação por tamanho)
  winsw\                stemma.exe (WinSW 2.12) + stemma.xml
D:\stemma-data\         STORAGE_ROOT: banco, stems, exports, cache do torch
  backups\              backups do banco feitos pelo update.ps1
```

- O serviço `stemma` roda `current\deploy\start.ps1`: carrega o `.env`, aplica as migrations e sobe o uvicorn (1 worker) em `127.0.0.1:8000`, servindo também o `frontend\dist` da release.
- Acesso de fora só pelo `tailscale serve`: `https://<pc>.<tailnet>.ts.net` → `http://127.0.0.1:8000`.

## Pré-requisitos (uma vez)

- **uv** (`winget install astral-sh.uv`). Ele instala o Python 3.12 se faltar.
- **FFmpeg** (`winget install Gyan.FFmpeg`) e **Deno** ou **Node** (o yt-dlp usa no YouTube).
- **Tailscale** logado, com HTTPS habilitado no tailnet (admin console → DNS → HTTPS Certificates).
- Driver NVIDIA (o torch cu118 vem no `uv sync`).

Tudo precisa estar no PATH **da sua conta**, porque o serviço roda com ela.

## Instalar

Num PowerShell **como administrador**:

```powershell
# baixe stemma-vX.Y.Z.zip da GitHub Release, extraia em qualquer pasta e rode:
powershell -ExecutionPolicy Bypass -File .\stemma-vX.Y.Z\deploy\install.ps1
```

O script baixa de novo a release (a última, ou `-Version vX.Y.Z`) e confere o SHA256, extrai, cria o venv (`uv sync`, alguns minutos na primeira vez por causa do torch), cria `C:\stemma\.env`, registra o serviço e configura o `tailscale serve`. O WinSW pede a conta (ex.: `.\Dell`) e a senha do Windows, e se pode conceder "logon como serviço" (responda `y`).

Parâmetros: `-ZipPath` (pacote local, com o `.sha256` ao lado), `-Root`, `-DataRoot`, `-Port`, `-ServiceId` e `-SkipTailscale` (os três últimos para ensaio).

## Atualizar

```powershell
powershell -ExecutionPolicy Bypass -File C:\stemma\current\deploy\update.ps1            # última release
powershell -ExecutionPolicy Bypass -File C:\stemma\current\deploy\update.ps1 -Version v1.3.1
```

Etapas: download + SHA256 → extração lado a lado → `uv sync` (com o serviço ainda no ar) → para o serviço → backup do banco em `D:\stemma-data\backups\` → `alembic upgrade head` → `current` aponta para a nova → sobe → espera o `/health` responder com a versão nova (até 3 min). Ficam as 3 releases mais novas.

**Se qualquer etapa depois de parar o serviço falhar**, o script restaura o banco do backup, volta o `current`, sobe a versão anterior, confere o `/health` dela e sai com código 1.

Para testar o rollback: `update.ps1 -Version vX.Y.Z -SimulateFailure`. A checagem do `/health` falha de propósito e o rollback roda.

No celular, o app avisa "Nova versão disponível" com o botão **Recarregar**.

## Voltar versão (rollback manual)

```powershell
powershell -ExecutionPolicy Bypass -File C:\stemma\current\deploy\update.ps1 -Rollback
```

Volta para a release instalada imediatamente anterior. Faz backup do banco, desfaz as migrations até o head daquela release (`alembic downgrade`), troca o `current` e sobe. Os dados novos continuam no banco; só o schema volta.

## Só o yt-dlp

Quando o YouTube quebra o download e já saiu um yt-dlp novo:

```powershell
powershell -ExecutionPolicy Bypass -File C:\stemma\current\deploy\update.ps1 -YtDlpOnly
```

Atualiza o yt-dlp no venv da release atual e reinicia o serviço. O `/health` mostra a versão (`ytdlp`). O próximo update normal volta para a versão do `uv.lock` da release.

## Cookies do YouTube

Se o download falhar com "YouTube pediu login. Atualize os cookies.":

1. Exporte os cookies do youtube.com no formato Netscape (extensão "Get cookies.txt LOCALLY", logado numa conta).
2. Salve em `D:\stemma-data\cookies.txt`.
3. No `C:\stemma\.env`: `YTDLP_COOKIE_FILE=D:\stemma-data\cookies.txt`.
4. Reinicie: `Restart-Service stemma` (como administrador).

## Logs e serviço

```powershell
Get-Content C:\stemma\logs\stemma.err.log -Tail 50 -Wait   # o log do app vai para o stderr
Get-Service stemma
Restart-Service stemma
Invoke-RestMethod http://127.0.0.1:8000/health
tailscale serve status
```

O serviço reinicia sozinho se o processo cair (10 s, 30 s, depois a cada 60 s).

Para remover tudo (o `D:\stemma-data` fica):

```powershell
C:\stemma\winsw\stemma.exe stop; C:\stemma\winsw\stemma.exe uninstall
tailscale serve --https=443 off
Remove-Item -Recurse -Force C:\stemma
```

## App no celular (PWA)

1. Abra `https://<pc>.<tailnet>.ts.net` no Chrome do Android (sem `:5183`, que é o Vite do dev).
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
