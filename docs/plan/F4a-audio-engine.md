# F4a — Protótipo e núcleo do AudioEngine

## Objetivo
Provar no celular real que 4 stems tocam sincronizados, com baixo consumo de memória, antes de construir a UI do mixer ([ADR 0006](../decisions/0006-audio-no-celular.md)).

## Escopo
- **Decidir a variação do mixer no celular** com o usuário (ver "Decisões pendentes" em `docs/design/README.md`) e registrar a decisão lá.
- `src/audio/AudioEngine.ts` (sem React): carregar 4 stems por streaming; grafo `MediaElementSource → Gain → StereoPanner → destino`; play/pause/seek; volume, pan, mute, solo; loop A–B; relógio mestre e re-sync periódico (medir drift e corrigir acima de um limiar); `resume()` no gesto; `visibilitychange`; `navigator.audioSession.type = "playback"`; `dispose()` fechando o `AudioContext`; eventos (`timeupdate` throttled, `ended`, `error`).
- Componente de waveform a partir dos **peaks** do backend (wavesurfer com `peaks` ou canvas próprio — decidir e registrar) + playhead por rAF sem re-render.
- Página de **teste técnico** em `/dev/engine` (só em dev): carrega uma sessão, mostra drift medido entre stems, memória aproximada, controles crus.
- Medir em **Android e iPhone** (se disponível): drift ao longo de 3 min, memória, retomada após bloquear a tela, troca de aba. Se o drift for inaceitável, avaliar fallback `AudioBufferSourceNode` (só desktop) e registrar em ADR.
- Testes unitários da lógica pura do engine (estado de mute/solo efetivo, cálculo de loop, política de re-sync) com AudioContext mockado.

## Fora do escopo
UI final do mixer e export (F4b).

## Checklist
- [x] variação do mixer no celular decidida e registrada
- [x] AudioEngine completo
- [x] waveform por peaks + playhead
- [x] página /dev/engine
- [ ] medições no celular registradas no Handoff (números)
- [x] ADR atualizada se houver fallback
- [x] testes

## Critério de pronto
4 stems tocando sincronizados no celular por 3+ minutos, drift medido abaixo do limiar definido, sem crash; números registrados no Handoff; CI verde.

## Handoff
**Status:** em andamento (2026-10-05). PR aberto; falta a medição no Android (ver "Pendente").

### Feito
- **Decisão do mixer no celular**: 1f (Modo prática) é a tela inicial, "Ajustar" abre 1e (Lanes compactas) e a paisagem usa o 1g. Registrada em [docs/design/README.md](../design/README.md#decisões-pendentes).
- **`src/audio/`** (sem React), detalhes na [ADR 0012](../decisions/0012-audio-engine-sincronia.md):
  - `mixLogic.ts`: ganho efetivo (regra de mute/solo da ADR 0010), loop A–B e política de re-sync;
  - `clock.ts`: `MasterClock` ancorado no `AudioContext.currentTime`;
  - `AudioEngine.ts`: 4 `<audio>` → Gain → StereoPanner; play/pause/seek, volume/pan/mute/solo com rampa, loop A–B, re-sync a cada ~1 s contra a mediana dos stems (30 ms; velocidade ±2% até 150 ms, seek acima disso), pausa conjunta no `waiting`, pausa externa, `visibilitychange`, `audioSession`, eventos e `dispose()` fechando o contexto.
- **`src/features/mixer/`**: `Waveform` em canvas a partir dos peaks (tocado opaco, restante a 35%, mudo tracejado, região A–B), `resamplePeaks`, e os hooks `useAudioEngine`, `usePlayhead` (rAF escrevendo `--progress` e o tempo, sem re-render), `usePlaybackState`, `useEngineStats` e `usePeaks`.
- **API**: `stemUrl` e `getPeaks` em `src/api/endpoints.ts`; tipos `Stem`, `StemMix`, `MixState` e `StemPeaks`. `formatClock` (`1:12.4`) em `lib/format.ts`.
- **`/dev/engine`** (só em dev, fora do bundle de produção): controles crus, desvio por stem, espalhamento, correções, travadas, heap e medição com relatório JSON copiável.
- **Testes**: 119 no total (38 novos): `mixLogic`, `clock`, `AudioEngine` com `AudioContext`/`<audio>` falsos (`src/test/audio.ts`), `resamplePeaks`, resumo e gravador da medição, e a página `/dev/engine` de ponta a ponta.
- **`/code-review`**: 3 achados, todos corrigidos com teste:
  - um stem que acabava antes do B parava a música em vez de repetir o loop;
  - o `waiting` de um seek contava como travada;
  - o gravador não era parado ao sair da página.

### Medições
| Onde | Duração | Leituras | Espalhamento máx / médio / p95 | Correções (vel./seek) | Travadas | Heap JS |
|---|---|---|---|---|---|---|
| Desktop, Edge 153 headless (Windows, sessão ST-002, 4:05) | 185 s | 182 | 2,9 / 0,1 / 0,2 ms | 0 / 0 | 0 | 15,9 → 15,7 MB |
| Android (Chrome, via Tailscale) | _pendente_ | | | | | |

### Pendente
- **Medição no Android** (critério de pronto): abrir `https://<máquina>.<tailnet>.ts.net:5183/dev/engine`, escolher uma sessão, Tocar, "Iniciar medição", deixar 3+ min (bloquear a tela e trocar de aba no meio), "Parar e gerar relatório" e colar o JSON aqui.
- iPhone: sem aparelho nesta fase; fica para conferir quando houver.
- Herdado: branch protection (F0).

### Decisões
- [ADR 0012](../decisions/0012-audio-engine-sincronia.md): desvio medido contra a mediana dos stems, limiar de 30 ms, waveform em canvas próprio e **sem fallback `AudioBufferSourceNode`** (o desktop ficou em ~3 ms sem nenhuma correção).
- O componente de waveform e os hooks de engine ficam em `features/mixer/`, para a F4b reaproveitar.

### Pegadinhas
- **HMR mata a medição**: editar qualquer arquivo do frontend com o `/dev/engine` aberto recarrega o módulo e descarta o engine. Não mexa no código durante uma medição.
- **`performance.memory`** só existe no Chromium e mede só o heap JS. Os buffers de mídia não aparecem.
- **`currentTime` dos `<audio>`** mede a linha do tempo da mídia, não a saída de som. A conferência final da sincronia é de ouvido.
- **Testes com áudio**: o jsdom não tem `AudioContext` nem toca mídia. Use `fakeAudio()` (`src/test/audio.ts`) ou `vi.stubGlobal('AudioContext'|'Audio', …)`. Não use `vi.unstubAllGlobals()`, porque ele desfaz o WebSocket falso do setup.
- **Teste intermitente da F3**: "busca com debounce vai para a URL" (`LibraryPage.test.tsx`) falhou uma vez com a suíte inteira sob carga e passou nas repetições.
- **CI da main**: os runs dos merges #10 e #11 falharam por infraestrutura ("job was not acquired by Runner"), não por código.

### Pendências descobertas
- Nenhuma fora do escopo das próximas fases.
