# F2b — Pipeline de áudio real

## Objetivo
Substituir o pipeline falso pelo real: busca e download via yt-dlp, separação com Demucs, MP3, métricas, peaks e export.

Referência de lógica: [docs/reference-v1.md](../reference-v1.md).

## Escopo
- `pipeline/download.py`: busca (`GET /api/search?q=` → título, canal, duração, thumbnail, url; até 10 resultados; distinguir "nenhum resultado" de "YouTube indisponível") e download `bestaudio` com `js_runtimes`, `cookiefile` (`YTDLP_COOKIE_FILE`) e mensagens amigáveis (ex.: `youtube_login_required` → "YouTube pediu login. Atualize os cookies."). Pré-preenche artista/título a partir dos metadados.
- `pipeline/separate.py`: Demucs via **subprocess** ([ADR 0004](../decisions/0004-pipeline-via-subprocess.md)) com modelo/segment/overlap/shifts da config, fallback cuda→cpu, progresso parseado da saída quando possível, timeout, cancelamento matando o processo.
- `pipeline/audio.py` (único lugar com ffmpeg): MP3 dos stems, `loudnorm` para métricas (LUFS, true peak), **peaks** por stem (`{stem}.peaks.json`, ~800–2000 pontos por stem, + duração), mixdown com volume/pan por stem para export **WAV** e **MP3 320**.
- Fluxo do job de processamento: downloading → separating → (mp3 + peaks + métricas) → ready; cada etapa persiste estado/progresso e publica evento.
- Exports: `POST /api/sessions/{id}/exports` (formato + mix atual) → job no worker leve; `GET /api/sessions/{id}/exports`; `GET /api/exports/{id}/file` (download com nome `Artista - Título (Preset).ext`).
- Servir stems e peaks: `GET /api/sessions/{id}/stems/{stem}.mp3` (com suporte a Range) e `.../peaks/{stem}.json`.
- Limpeza: excluir sessão/reprocessar remove `raw/` e `stems/` antigos; CLI `python -m app.cli cleanup` para órfãos.
- `/health` passa a reportar `gpu` (cuda disponível?), versão do yt-dlp, presença de ffmpeg e runtime JS.
- Testes: unitários com subprocess mockado (comandos montados corretamente, erros mapeados, timeouts), parse do loudnorm, geração de peaks com um WAV sintético curto (ffmpeg disponível no CI via apt), mixdown com 2 stems sintéticos.

## Fora do escopo
Qualquer UI (F3/F4).

## Checklist
- [x] busca + download + mapeamento de erros
- [x] Demucs via subprocess + fallback + cancelamento
- [x] audio.py: mp3, métricas, peaks, mixdown wav/mp3
- [x] job de processamento completo com eventos
- [x] exports + download
- [x] servir stems (Range) e peaks
- [x] limpeza de arquivos + CLI cleanup
- [x] `/health` completo
- [x] testes

## Critério de pronto
No PC: buscar uma faixa, processar de ponta a ponta (stems MP3, peaks, métricas no banco), exportar WAV e MP3 e baixar; cancelar um job em separação libera a GPU; CI verde.

## Handoff
**Status:** concluída em 2026-10-05, PR #8 (`feat: pipeline de áudio real (F2b)`).

### Feito
- **`pipeline/proc.py`**: base de subprocess com timeout, stderr em linhas (`
` e `
`, para barras de progresso), `on_poll` na thread do job (onde se grava progresso) e cancelamento por `taskkill /F /T` no Windows.
- **`pipeline/audio.py`** (único lugar com ffmpeg): MP3 320 dos stems, `loudnorm` (LUFS e true peak), peaks e mixdown WAV/MP3 320 com volume e pan iguais ao Web Audio.
- **`pipeline/download.py`**:
  - busca in-process (texto via `ytsearch10:` ou link), com timeout total e sugestão de artista/título;
  - download `bestaudio` como **subprocess** (`python -m yt_dlp`), com runtimes JS, cookies, progresso, cancelamento e timeout total;
  - erros mapeados: `youtube_login_required`, `age_restricted`, `video_unavailable`, `youtube_format_unavailable`, `youtube_unavailable`, `download_failed`, `download_timeout`.
- **`pipeline/separate.py`**: Demucs via `python -m demucs.separate`, com progresso parseado do tqdm (bags e shifts), fallback cuda→cpu só para erro de GPU, timeout e cancelamento.
- **`pipeline/handlers.py`**:
  - `ProcessHandler`: baixando → separando (Demucs 0–90%, MP3+peaks 90–98%, métricas) → `ready`;
  - `ExportHandler`: mixdown + LUFS do arquivo.
- **Fila**: o job `export` espelha estado/progresso em `exports` e publica `export.updated`. Cancelar um export o marca `failed`/`cancelled`.
- **Rotas**:
  - `GET /api/search?q=`;
  - `POST|GET /api/sessions/{id}/exports`, `GET /api/exports/{id}/file`;
  - `GET /api/sessions/{id}/stems/{stem}.mp3` (Range) e `GET /api/sessions/{id}/peaks/{stem}.json`.
- **CLI** `python -m app.cli cleanup [--dry-run] [--min-age-minutes 60]` (`services/cleanup.py`). Só remove o que está parado há 60+ min, então é seguro com o app no ar.
- **`/health`**: `gpu` (sonda em subprocess, em segundo plano), `ytdlp` (versão) e `js_runtime` (algum da lista).
- **Config**: `YTDLP_JS_RUNTIME` (lista), `YTDLP_COOKIE_FILE`, `SEPARATION_MODEL`, `DEMUCS_*`, `TORCH_HOME` e timeouts. `FFPROBE_BIN` saiu (não é usado).
- **Dependências**: `yt-dlp[default]>=2025.11.12` (traz o `yt-dlp-ejs`, exigido pelo YouTube) e `pydantic-settings>=2.7` (`NoDecode`). CI instala ffmpeg via apt.
- **Code review** (`/code-review`), 4 achados corrigidos:
  - download sem timeout/cancelamento antes do 1º byte → virou subprocess;
  - `"not available"` genérico → `youtube_format_unavailable`;
  - pisos de versão;
  - corrida do cleanup com o app no ar → idade mínima.
  - De carona: stems pela metade são apagados quando o job falha ou é cancelado.
- **Testes**: 227 (pytest). Os novos ficam em:
  - `test_proc`, `test_audio` (ffmpeg real com senos sintéticos), `test_download` (YoutubeDL falso na busca e `yt_dlp` falso via `PYTHONPATH` no download);
  - `test_separate` (módulo `demucs` falso via `PYTHONPATH`);
  - `test_pipeline` (handlers reais com download/Demucs falsos);
  - `test_exports_api`, `test_media_api`, `test_search_api`, `test_cleanup`.
- **Verificação no PC** (uvicorn real, sem pipeline falso, GTX 1650):
  1. Busca "the beatles let it be" → sessão → processada em ~80 s (download ~20 s, Demucs na GPU ~35 s, MP3+peaks+métricas ~24 s).
  2. 4 MP3 + 4 peaks (1600 pontos), `metrics` no banco, `raw/` e `work/` apagados; Range → 206.
  3. Export WAV (PCM 16 bit, 44,1 kHz) e MP3 (320 kbps) baixados como `The Beatles - Let It Be (Sem voz).ext`.
  4. Cancelar em "Separando" → 204, sessão `failed`/`cancelled`, nenhum `demucs` vivo e VRAM de volta a 86 MiB.
  5. Depois do review: cancelar no meio de um download real (vídeo de 1 h, em 72%) matou o `yt_dlp` em ~4 s.
  6. `/health` com `gpu: ok` e `ytdlp: 2026.08.19`.

### Contrato da API (para F3/F4)
- **Busca**: `GET /api/search?q=` → `{items: [{source_url, source_title, source_channel, duration_s, thumbnail_url, artist, title}]}`. O item vai direto no `POST /api/sessions` (o usuário confirma artista/título antes). `items: []` = nenhum resultado; 502 `youtube_unavailable` = YouTube fora do ar (mostrar "Tentar de novo"); 422 `video_unavailable` para link inválido.
- **Sessão pronta**: `stems` lista os stems; `metrics: {lufs, true_peak_db} | null`; `duration_s` passa a ser a medida real.
- **Player**: `/api/sessions/{id}/stems/{stem}.mp3` (aceita Range, `Cache-Control: no-cache`) e `/api/sessions/{id}/peaks/{stem}.json` → `{duration_s, peaks: number[]}` (0–1).
- **Export**:
  - `POST /api/sessions/{id}/exports` com `{format: "wav"|"mp3", preset?, stems?}`; sem `stems`, usa o mix salvo;
  - erros: 409 `session_not_ready`, 422 `no_active_stems`;
  - `ExportOut` traz `state` (`queued|running|done|failed`), `progress`, `size_bytes`, `lufs`, `file_name` e `stems` (snapshot);
  - o progresso chega por `export.updated` no `/ws`; download em `GET /api/exports/{id}/file`.
- **Dock**: exports não aparecem como encerrados no `/api/jobs` (ver Decisões). Ativos aparecem com `kind=export`; o dock da F3 deve filtrar `kind === "process"`.
- **Erros do processamento** (em `session.error_code`): `youtube_login_required`, `age_restricted`, `video_unavailable`, `youtube_format_unavailable`, `youtube_unavailable`, `download_failed`, `download_timeout`, `separation_failed`, `separation_timeout`, `demucs_missing`, `ffmpeg_missing`, `ffmpeg_failed`, `ffmpeg_timeout`, `cancelled`, `interrupted`.

### Para a F4a
- O export soa igual ao mixer se o AudioEngine usar `GainNode` com `volume/100` e `StereoPannerNode` com `pan` ([ADR 0010](../decisions/0010-pipeline-de-audio.md)).
- Peaks: 1600 pontos por stem; para a waveform, escalar para a largura da lane.

### Pendente
- Itens herdados: teste no celular via Tailscale e branch protection (F0).

### Decisões
- [ADR 0010](../decisions/0010-pipeline-de-audio.md):
  - layout de arquivos, peaks e métricas;
  - mixdown com as leis do Web Audio e regra de mute/solo;
  - exports fora do dock, sonda da GPU e `YTDLP_JS_RUNTIME` como lista.
- **Solo + mute**: um stem solado e mudo não conta como solo (decidido na implementação; a v1 não tratava o caso).
- **Áudio baixado** é apagado ao fim do job; reprocessar baixa de novo.
- **Métricas** medidas no áudio original, não na soma dos stems (resultado equivalente, uma etapa a menos).

### Pegadinhas
- **Deno não está instalado** neste PC; o yt-dlp usa o Node (padrão `deno,node`).
- **`-ac 2` do ffmpeg 8** atenua mono → estéreo em 3 dB. O fixture `sine_wav` duplica o canal com `pan` para os testes de nível baterem.
- **Testes e GPU**: o fixture autouse `_no_gpu_probe` desliga a sonda (senão cada app de teste importaria o torch num subprocess). O fixture `client` agora passa `job_handlers={}` explicitamente, porque o padrão virou o pipeline real.
- **Demucs e yt-dlp falsos nos testes**: um pacote `demucs` (ou `yt_dlp`) num diretório temporário no `PYTHONPATH` substitui o real no subprocess.
- **Progresso gravado só na thread do job**: o `on_line` do `run_process` roda na thread leitora; grave no banco só no `on_poll`.
- **Matar o servidor no Windows**: `taskkill /F /T` no PID que escuta a porta (como na F2a).
- **mypy no Linux (CI)**: atributos só do Windows (ex.: `subprocess.CREATE_NO_WINDOW`) precisam ficar sob `if sys.platform == "win32":` em forma de bloco, e não num ternário. Confira localmente com `uv run mypy app --platform linux`.

### Pendências descobertas
- Nenhuma fora do escopo das próximas fases.
