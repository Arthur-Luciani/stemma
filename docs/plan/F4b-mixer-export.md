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
- [x] componentes de controle com testes
- [x] mixer desktop completo
- [x] mixer celular (retrato + paisagem)
- [x] atalhos
- [x] presets + Personalizado
- [x] persistência do mix
- [x] export + download
- [ ] conferido no celular real e no desktop (desktop: capturas + export real pela API; falta a conferência do usuário, ver "Pendente")

## Critério de pronto
No celular e no desktop: abrir uma sessão, mixar, usar loop A–B, aplicar preset, recarregar a página e encontrar o mix salvo, exportar MP3 e baixar; CI verde.

## Handoff
**Status:** PR aberto (2026-10-05). Falta a conferência no celular real e no desktop, que é sua (ver "Pendente").

### Feito
- **Rota `/sessions/:id/mix`** (`features/mixer/MixerPage.tsx`) no lugar do placeholder da F3. Sessão que não está pronta mostra um estado vazio com "Abrir sessão".
  - Uma tela por sessão (`key`): trocar de sessão recria o engine e o mix.
  - No celular a rota é **tela cheia** (`handle: { fullscreen: true }`): sem bottom nav e sem pílula.
- **Estado do mixer** ([ADR 0013](../decisions/0013-estado-do-mixer.md)):
  - `mixState.ts` (puro): presets por mute + volume 100, preset **derivado** do mix ("Personalizado" quando não bate), reducer, loop A–B (`markA`/`markB`/`loopFromDrag`), `formatPan`;
  - `useMixer.ts`: carrega uma vez, aplica no `AudioEngine` na hora e salva com debounce de 600 ms (lido por `ref`, fila de saves, flush no unmount, no `pagehide`/`visibilitychange` com `keepalive` e antes do export).
- **Componentes** (`features/mixer/`): `Fader` (horizontal/vertical, teclado, duplo toque = 100%), `PanControl` (slider e knob, duplo toque = C), `MuteSoloButton`, `PresetSelector` (segmented, pílulas e grade do 1f com "Personalizado"), `Transport` (4 tamanhos), `LoopABControl`, `MetricsBadge`, `TimeRuler`, `MixWaveform` (soma dos peaks × ganho efetivo) e `timeline.ts` (toque = seek, arrasto = loop, com prévia).
- **Desktop** (`DesktopMixer`): cabeçalho com editar (reusa `EditSessionDialog`, em `?edit=1`), presets, barra de transport com A/B, LUFS/dBTP e Exportar (popover em `?export=1`), régua, 4 lanes com waveform do stem (mudo = 30% + tracejado), região A–B e playhead atravessando as lanes, dicas de atalho.
- **Atalhos** (`shortcuts.ts`): Espaço, ← →, 1–4, ⇧1–4 (por `event.code`), A/B. São ignorados em campo de texto, dentro de diálogo, com Ctrl/⌘/Alt e na repetição (só o ±5 s repete). Sliders e presets param a propagação das setas.
- **Celular**: 1f `PracticeMixer` (padrão), 1e `LanesMixer` em `?view=ajustar` (pan fino num sheet em `?pan=<stem>`), 1g `ConsoleMixer` em paisagem (`(orientation: landscape) and (max-height: 600px)`), M6 `ExportSheet` em `?export=1`. O back do Android fecha sheet → volta ao 1f.
- **Export** (`ExportPanel.tsx`): WAV/MP3 320, salva o mix antes do `POST`, progresso ao vivo pelo `export.updated` (agora tratado em `applyLiveEvent`), lista "Anteriores" com data, tamanho, LUFS e Baixar (`/api/exports/{id}/file`).
- **API do client**: `getMix`, `saveMix` (com `keepalive`), `listExports`, `createExport`, `exportFileUrl`; chaves `mix` e `exports`.
- **Testes**: 176 no total (57 novos): estado e presets, `useMixer` (debounce, flush, retry, engine), controles, atalhos, linha do tempo, `mixPeaks`, formatadores e páginas (desktop, atalhos, recarregar, export ao vivo, celular 1f → 1e → sheet de pan → back).
- **`/code-review`**: 3 achados, todos corrigidos:
  - se o save do mix falhava, o export saía com o mix salvo antigo (agora `flush()` diz se salvou e o export para; com teste);
  - a resposta do `POST /exports` podia sobrescrever um estado mais novo que já tinha chegado pelo `/ws`;
  - Espaço num botão focado (M, S, preset, Exportar) tocava a música em vez de acionar o botão (com teste).
- **Conferido ao vivo** (backend local, sessão ST-002):
  - capturas do Edge headless no desktop (1440×900), retrato e paisagem;
  - export MP3 pela API: `PUT /mix` (Sem voz) → `POST /exports` → `done` em ~10 s, 9,8 MB, −15,2 LUFS, download com `Content-Disposition` "Survivor - Eye Of The Tiger (Sem voz).mp3". Depois o mix da ST-002 voltou ao Original.

### Pendente
- **Conferência no celular real** (critério de pronto) via Tailscale: abrir uma sessão, mixar no 1e, marcar loop arrastando no 1f, aplicar preset, girar para paisagem, recarregar e achar o mix, exportar MP3 e baixar.
- **Medição do AudioEngine no Android** (herdada da F4a): `/dev/engine`, 3+ min com tela bloqueada e troca de aba, colar o JSON no Handoff da F4a.
- **Conferência no desktop** com mouse e ouvido: atalhos, arrastar nas lanes, popover de export e download pelo navegador.
- iPhone: sem aparelho.
- Herdado: branch protection (F0).

### Decisões
- [ADR 0013](../decisions/0013-estado-do-mixer.md): presets por mute + volume 100 (decidido com o usuário), preset derivado do mix, estado local como verdade enquanto a tela está aberta, save com debounce e flush.
- Desvios do design registrados em [docs/design/README.md](../design/README.md#desvios) (tela cheia no celular, A/B no desktop, MP3 como formato inicial, LUFS do original no transport).
- Os componentes de controle ficam em `features/mixer/`, não em `ui/`: só o mixer usa.

### Pegadinhas
- **Edge/Chrome headless não fica com menos de ~500px de largura.** `--window-size=390,844` desenha a 500px e corta a imagem, e o layout parece vazar à direita. Para conferir o celular, use o aparelho ou o DevTools com emulação.
- **TanStack Query avisa a tela num `setTimeout`.** Depois de `FakeWebSocket.receive()` dentro de `act()`, use `findBy…`/`waitFor`, não `getBy…`.
- **jsdom não tem pointer capture**: `src/test/setup.ts` tem um polyfill de `setPointerCapture`/`hasPointerCapture`, que solta no `pointerup`. `fireEvent.pointerDown` cria `PointerEvent` com `clientX` e `pointerId`.
- **Duplo toque nos testes**: dois `pointerDown` seguidos no mesmo controle contam como duplo (são < 300 ms). Teste arrasto e duplo toque em renders separados.
- **`stubAudioGlobals()`** (`src/test/audio.ts`) troca `AudioContext`/`Audio` para as páginas do mixer. Mocke também `HTMLCanvasElement.prototype.getContext` (a waveform desenha em canvas).
- **Teste da busca da biblioteca**: era a intermitência anotada na F4a. O `expect` do GET vinha depois do `waitFor` da URL. Agora espera pelos dois.

### Pendências descobertas
- Nenhuma fora do escopo das próximas fases.
