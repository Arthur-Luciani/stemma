# 0010 — Pipeline de áudio: arquivos, peaks, mixdown e exports

- **Status:** aceita (2026-10-05)
- Complementa a [0004](0004-pipeline-via-subprocess.md) e a [0009](0009-workers-em-threads-e-eventos.md).

## Contexto
A F2b plugou o pipeline real (yt-dlp → Demucs → ffmpeg) na fila da F2a. Várias escolhas afetam o frontend (F4a/F4b) e a operação (F5): onde ficam os arquivos, o formato dos peaks, como o export reproduz o mixer do navegador, como a GPU é verificada e onde os exports aparecem.

## Decisão

### Arquivos (relativos ao `STORAGE_ROOT`, via `Storage`)
```
sessions/{id}/raw/source.<ext>          download (apagado ao fim do job, com sucesso ou não)
sessions/{id}/work/demucs/…             WAVs do Demucs (idem)
sessions/{id}/stems/{stem}.mp3          MP3 320 kbps de cada stem
sessions/{id}/stems/{stem}.peaks.json   waveform
sessions/{id}/exports/{export_id}.wav|mp3
```
- Reprocessar apaga `raw/`, `work/` e `stems/` **no início** do job e zera `stems`/`metrics` da sessão. Os exports antigos ficam.
- Os paths dos stems no banco (`sessions.stems`) são relativos; os peaks são derivados do layout.

### Peaks
- `{"duration_s": float, "peaks": [0–1, …]}`: o pico absoluto por bucket, em mono a 8 kHz, com **1600 pontos** e 3 casas.
- Gerados do WAV do Demucs (sem o atraso do encoder MP3).
- A `duration_s` da sessão passa a ser a medida na decodificação, e não a do YouTube.

### Métricas
- `sessions.metrics = {"lufs", "true_peak_db"}`, medidas com `loudnorm` no **áudio original** baixado. Valor `-inf` (silêncio) vira `null`.
- O export guarda o LUFS do próprio arquivo exportado.

### Mixdown (igual ao mixer do navegador)
- Volume **linear**: `ganho = volume / 100`.
- Pan com a **mesma lei do `StereoPannerNode`** do Web Audio para entrada estéreo (equal-power). O F4a deve usar `StereoPannerNode` + `GainNode` para o export soar igual ao que se ouve.
- Mute e solo:
  - com algum solo, só os solados tocam;
  - mute sempre tira o stem;
  - um stem solado **e** mudo não conta como solo.
- Soma com `amix=normalize=0`. Saída a 44,1 kHz: WAV PCM 16 bit ou MP3 `libmp3lame` 320 kbps.

### Exports
- `POST /api/sessions/{id}/exports` grava um snapshot dos níveis (do corpo ou, sem `stems`, do mix salvo) e cria um job `export` no worker leve.
- O job espelha estado e progresso na linha de `exports` e publica `export.updated`, como o `process` faz com a sessão.
- **Exports não ficam no dock**: o job de export encerrado (pronto, falho ou cancelado) recebe `dismissed_at` na hora. Enquanto ativo, aparece no `/api/jobs` com `kind=export`. O lugar dele é a lista de exports da sessão.
- O download tem o nome `Artista - Título (Preset).ext` (rótulo PT-BR do preset; caracteres inválidos no Windows saem).

### yt-dlp
- Usa o extra `yt-dlp[default]` (≥ 2025.11.12), que traz o `yt-dlp-ejs`, exigido pelo YouTube junto com um runtime JS.
- O **download** roda como **subprocess** (`python -m yt_dlp`), como o Demucs. In-process, o timeout e o cancelamento só valiam enquanto chegavam bytes (no hook de progresso); um yt-dlp travado no desafio JS prendia o worker da GPU. O progresso vem de um `--progress-template` próprio.
- A **busca** continua in-process (é rápida e não grava nada), com timeout total de 45 s numa thread à parte.
- `YTDLP_JS_RUNTIME` virou **lista** (padrão `deno,node`): o yt-dlp usa o primeiro instalado, e o `/health` dá `ok` se algum existir.
- A busca **nunca** devolve lista vazia por erro: YouTube fora do ar é 502 `youtube_unavailable`.
- `Requested format is not available` vira `youtube_format_unavailable` (aponta para yt-dlp/runtime JS), e não "vídeo indisponível".
- Os resultados já trazem `artist`/`title` sugeridos e os mesmos campos do `SessionCreate`.

### Demucs
- `python -m demucs.separate` com o mesmo Python do app e `TORCH_HOME` só no ambiente do filho.
- O progresso vem das barras do tqdm, contando as barras de modelos-bag e de shifts.
- `DEMUCS_DEVICE=auto` tenta `cuda` e repete em `cpu` **só** se o erro parecer de GPU (CUDA, memória, cuDNN). Outros erros não repetem.
- Cancelar mata a árvore do processo (`taskkill /F /T` no Windows), e a VRAM é liberada na hora.

### GPU no `/health`
- A sonda é um subprocess (`import torch; torch.cuda.is_available()`) disparado no startup em segundo plano. O processo da API nunca importa o torch.
- Até a sonda responder, `gpu = unknown`.

### Limpeza
- `python -m app.cli cleanup` pode rodar com o app no ar. Só remove o que está parado há mais de `--min-age-minutes` (padrão 60), porque um job que começou depois do retrato do banco estaria mexendo nos arquivos.

## Consequências
- O frontend tem contrato estável para tocar (`/stems/{stem}.mp3` com Range, `/peaks/{stem}.json`) e para exportar.
- O export reproduz o mixer desde que a F4a use as mesmas leis de volume e pan.
- Um reprocessamento que falha deixa a sessão sem stems (`failed`); é preciso processar de novo.
- O CI instala o ffmpeg via apt; os testes de áudio usam ffmpeg real com sinais sintéticos.
