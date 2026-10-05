# 0004 — Pipeline isolado em `pipeline/`, Demucs e ffmpeg via subprocess

- **Status:** aceita (2026-10-05)

## Contexto
Na v1 o Demucs rodava dentro do processo da API (`demucs_main`), sem liberar VRAM, alterando `os.environ` de uma thread e sem cancelamento. O ffmpeg era chamado com binário fixo, sem timeout e descartando o stderr.

## Decisão
- Demucs e ffmpeg sempre como **subprocess** com timeout, stderr capturado no erro e binário vindo da config.
- yt-dlp pode rodar in-process (biblioteca leve), sempre dentro de `pipeline/download.py`.
- Cancelamento = encerrar o subprocess.
- O pipeline também gera os **peaks** de waveform (`stems/{id}/{stem}.peaks.json`).

## Consequências
VRAM liberada ao fim de cada job, falhas diagnosticáveis, testes mockam a fronteira de subprocess.
