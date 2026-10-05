# F4b — Mixer e Export

## Objetivo
Mixer completo no desktop e no celular, com estado persistido e export, conforme o design.

Antes de começar: abrir `Stemma - Desktop` (Mixer) e `Stemma - Celular` (variação escolhida na F4a + 1g paisagem + M6 Exportar) no Claude Design.

## Escopo
- Componentes: Fader (horizontal/vertical, duplo toque = 100%), PanControl (slider desktop / knob celular), MuteSoloButton, Transport, TimeDisplay (mono), LoopABControl, PresetSelector (com estado "Personalizado"), MetricsBadge (LUFS/dBTP).
- **Desktop**: cabeçalho com edição de identidade, presets segmentados, barra de transport com A–B, métricas e Exportar (popover), régua de tempo, 4 lanes com waveform colorida (tocado opaco / restante 35%), região A–B, playhead, dicas de atalho.
- **Celular**: variação escolhida em retrato + console em paisagem; transport na zona do polegar; alvos ≥ 44px.
- **Atalhos (desktop)**: Espaço play · ← → 5s · 1–4 mute · ⇧1–4 solo · A/B marcar loop.
- **Presets**: Original, Sem voz, Sem bateria, Sem baixo, Só voz (níveis portados da v1); mudar qualquer controle → "Personalizado".
- **Persistência**: mix state salvo com debounce (sem closures velhas — estado lido no momento do envio), restaurado ao abrir; loop A–B incluído.
- **Export**: popover (desktop) / tela M6 (celular): formato WAV ou MP3 320, progresso ao vivo, lista de exports anteriores com tamanho/LUFS e Baixar.
- Stem mutado: cor a 30% + waveform tracejada.
- Testes: componentes de controle, mapeamento de atalhos, lógica de presets/"Personalizado", debounce de persistência.

## Fora do escopo
PWA, serviço, update (F5).

## Checklist
- [ ] componentes de controle com testes
- [ ] mixer desktop completo
- [ ] mixer celular (retrato + paisagem)
- [ ] atalhos
- [ ] presets + Personalizado
- [ ] persistência do mix
- [ ] export + download
- [ ] conferido no celular real e no desktop

## Critério de pronto
No celular e no desktop: abrir uma sessão, mixar, usar loop A–B, aplicar preset, recarregar a página e encontrar o mix salvo, exportar MP3 e baixar; CI verde.

## Handoff
_Preencher ao final da sessão._
