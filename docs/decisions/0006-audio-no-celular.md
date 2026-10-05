# 0006 — Áudio: AudioEngine fora do React e waveforms por peaks

- **Status:** aceita (2026-10-05); validada no protótipo da F4a e detalhada pela [ADR 0012](0012-audio-engine-sincronia.md)

## Contexto
A v1 baixava cada stem duas vezes e decodificava tudo (≈340 MB de PCM para 4 stems de 4 min — crash provável no iOS), re-renderizava o mixer a 60 fps, nunca fechava o `AudioContext` e tocava 4 `<audio>` sem re-sincronização.

## Decisão
- Waveforms desenhadas a partir de **peaks pré-calculados pelo backend** (wavesurfer com `peaks` + `duration`, ou canvas próprio); nada de decodificar stems para desenhar.
- **AudioEngine** (classe TS, sem React): 4 `<audio>` em streaming → `MediaElementSource` → gain/pan por stem; relógio mestre com re-sync periódico; loop A–B no engine.
- `resume()` síncrono no gesto do usuário; tratar `visibilitychange`; `navigator.audioSession.type = "playback"` no iOS; `close()` no dispose.
- Playhead e tempo atualizados por rAF via CSS var / ref, sem re-render React.
- Fallback a avaliar no protótipo: `AudioBufferSourceNode` (sync perfeito, custo de memória) apenas no desktop.

## Consequências
Memória baixa no celular. A sincronia entre streams precisa ser medida no protótipo (F4a) antes de construir a UI.
