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
- [ ] busca + download + mapeamento de erros
- [ ] Demucs via subprocess + fallback + cancelamento
- [ ] audio.py: mp3, métricas, peaks, mixdown wav/mp3
- [ ] job de processamento completo com eventos
- [ ] exports + download
- [ ] servir stems (Range) e peaks
- [ ] limpeza de arquivos + CLI cleanup
- [ ] `/health` completo
- [ ] testes

## Critério de pronto
No PC: buscar uma faixa, processar de ponta a ponta (stems MP3, peaks, métricas no banco), exportar WAV e MP3 e baixar; cancelar um job em separação libera a GPU; CI verde.

## Handoff
_Preencher ao final da sessão._
