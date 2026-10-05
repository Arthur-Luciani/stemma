# Referência: lógica da v1 que vale portar

Repo: `Arthur-Luciani/music-analyzer` (local `C:\git\music-analyzer`), commit de referência `5a2f825`.

**Porte a lógica, não a estrutura.** A v1 tem problemas de arquitetura documentados (god object `JobService`, cache em memória divergindo do banco, Demucs dentro do processo da API, paths absolutos no banco). Leia o trecho, entenda o comportamento e reescreva seguindo o `CLAUDE.md`.

| Assunto | Onde na v1 (`backend/app/…`) | O que aproveitar |
|---|---|---|
| Busca no YouTube | `use_cases/search_candidates.py` `_search_youtube`, `_looks_like_url` | opções do yt-dlp para busca (`ytsearchN:`), detecção de URL. **Não** engolir erro como "sem resultados". |
| Download | `use_cases/process_session.py` `_build_ytdlp_options` (~l.257), `_format_ytdlp_download_error`, `_find_downloaded_audio_file` | `bestaudio`, `js_runtimes` (Deno/Node), `cookiefile` via `YTDLP_COOKIE_FILE`, mensagens amigáveis para erro de login/cookie. |
| Demucs | `use_cases/process_session.py` `_run_demucs` (~l.114), `_resolve_demucs_devices`, `_normalize_demucs_output`, `_find_demucs_stem_file` | parâmetros (`SEPARATION_MODEL`, segment, overlap, shifts, stems), fallback cuda→cpu, localização dos arquivos de saída. Na v2 rodar como **subprocess** (`python -m demucs …`). |
| MP3 dos stems | `process_session.py` `_compress_to_mp3` (~l.206) | parâmetros do ffmpeg. Na v2 capturar stderr e usar timeout. |
| Métricas do master | `process_session.py` `_analyze_master_metrics`, `_probe_master_metrics` (~l.319–358) | `loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json` e parse do JSON de saída (LUFS, true peak). |
| Mixdown/export | `use_cases/manage_export.py` `_mix_stems_to_wav` (~l.84), `_resolve_export_stems` | filtro ffmpeg com volume/pan por stem. Na v2 vira `pipeline/audio.py` compartilhado e ganha MP3 320. |
| Código curto de sessão | `repositories/session_repository.py` (~l.69–88, tabela `session_counter`) | ideia do contador sequencial; na v2 prefixo `ST-` e modelado no ORM. |
| Identidade artista/título | `use_cases/save_music_identity.py`, `services/market_midi_matcher.py` `normalize_artist`/`normalize_title` | normalização de texto para o autocomplete. |
| Presets de mix | `frontend/src/hooks/useWorkspace.js` | níveis dos presets (Original, Sem voz, Sem bateria…). |
| Script de dev | `run-local-dev.ps1` | detecção do FFmpeg instalado via winget e env vars de GPU. |

**Não portar:** tudo de `analyze_drum_stem`, `generate_drum_midi`, `save_drum_corrections`, `match_market_midi`, `market_midi_*`, `ml/`, `brain/`, `SheetMusicView`, `DrumInspector*`, `MarketCatalog*`.
