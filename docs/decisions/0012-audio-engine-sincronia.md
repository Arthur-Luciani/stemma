# 0012 — AudioEngine: sincronia dos stems, waveform em canvas e página de teste

- **Status:** aceita (2026-10-05)
- Detalha a [0006](0006-audio-no-celular.md). Usa as leis de volume, pan e mute/solo da [0010](0010-pipeline-de-audio.md).

## Contexto
A ADR 0006 escolheu 4 `<audio>` em streaming com re-sync periódico, mas deixou para o protótipo (F4a) o que medir, quando corrigir e como desenhar a waveform. Também ficou em aberto o fallback `AudioBufferSourceNode`.

## Decisão

### Grafo e controles
- Cada stem é um `<audio>` (`new Audio()`, `preload="auto"`) ligado a `MediaElementSource → GainNode → StereoPannerNode → destino`.
  - O ganho é `volume/100`; com solo, só os solados tocam; mute sempre tira; solado e mudo não conta. É a mesma regra do export.
  - Ganho e pan mudam com `setTargetAtTime` (15 ms), sem cliques.
- O `AudioEngine` (`src/audio/`) não depende do React. A regra pura fica em `mixLogic.ts`.

### Sincronia
- **O desvio é medido em relação à mediana das posições dos 4 stems, não ao relógio do `AudioContext`.**
  - O que se ouve como "flam" é a diferença entre os stems.
  - Os `<audio>` e o `AudioContext` podem andar em ritmos levemente diferentes. Medir contra o contexto corrigiria os 4 o tempo todo.
- O **relógio mestre** (`MasterClock`, ancorado no `AudioContext.currentTime`) serve só para o playhead e o loop. Ele é reancorado na mediana quando se afasta mais de 50 ms.
- **Limiar: 30 ms** (decidido com o usuário). A cada ~1 s:
  - stem com desvio acima de 30 ms e até 150 ms: velocidade ±2% até voltar a menos de 10 ms;
  - acima de 150 ms: seek para a mediana.
- **Buffering**: se um stem dispara `waiting`, o engine pausa os quatro. Quando todos voltam a ter dados, retoma da posição do mais atrasado. Voltar os outros usa dados já baixados.
- Uma pausa que não veio do engine (perda de foco de áudio, fone desconectado) pausa todos.
- `play()` chama `ctx.resume()` e os `play()` dos `<audio>` de forma síncrona, ainda dentro do gesto do usuário.
- O laço de controle (loop A–B, fim, `timeupdate`, re-sync) roda num `setInterval` de 25 ms e também no `timeupdate` do primeiro `<audio>`. Esse evento continua com a aba em segundo plano, onde os timers são estrangulados.
- Ao voltar para a aba (`visibilitychange`), o engine retoma o contexto se foi suspenso e mede/corrige na hora.
- `navigator.audioSession.type = "playback"` quando existir (iOS).
- `dispose()` solta os `src`, desconecta os nós e fecha o `AudioContext`.

### Waveform
- **Canvas próprio**, sem wavesurfer. Os peaks do backend (1600 pontos) são reamostrados pelo máximo de cada trecho para barras de 2 px com 1 px de espaço.
- Redesenha só quando os peaks, o mute ou o tamanho mudam.
- A parte já tocada é uma segunda camada com `clip-path` lida da CSS var `--progress`. O `usePlayhead` escreve essa var por rAF, sem re-render React.
- Stem mudo: 30% de opacidade e barras tracejadas.

### Página de teste
- `/dev/engine` existe só com `import.meta.env.DEV` (rota lazy, fora do bundle de produção).
- Tem controles crus, desvio por stem, espalhamento, correções, travadas, heap JS e uma **medição** que gera um relatório JSON. O relatório traz espalhamento máximo, médio e p95, desvio máximo por stem, leituras acima do limiar, tempo oculto e memória.

### Fallback `AudioBufferSourceNode`
**Não adotado.** No desktop o espalhamento medido ficou em décimos de ms, sem nenhuma correção (números no Handoff da F4a). Só volta a ser avaliado se o celular passar do limiar.

## Consequências
- A F4b monta a UI sobre `AudioEngine` + `useAudioEngine`/`usePlayhead`/`Waveform` (`src/features/mixer/`).
- O `currentTime` dos `<audio>` mede a linha do tempo da mídia, não a saída de som. Diferenças de latência entre decodificadores não aparecem na métrica. Na prática, todos passam pelo mesmo `AudioContext`, e a conferência final é de ouvido.
- `performance.memory` só mede o heap JS (e só existe no Chromium). Os buffers de mídia ficam fora dele.
