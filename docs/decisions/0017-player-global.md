# 0017 — Player global: o engine é do app, não do mixer

- **Status:** aceita (2026-10-14)
- Muda o fim de vida do `AudioEngine` da [0012](0012-audio-engine-sincronia.md). Mantém o save do mixer da [0013](0013-estado-do-mixer.md).
- Issue [#44](https://github.com/Arthur-Luciani/stemma/issues/44).

## Contexto
O `AudioEngine` nascia e morria com o mixer: sair para a Biblioteca ou o Descobrir fechava o `AudioContext` e a música parava. O uso real é ouvir enquanto se navega (e, depois, uma fila de reprodução, issue #45), então o engine precisa viver mais que a tela.

## Decisão

### Dono do engine
- Um **`Player`** (`src/audio/player.ts`, instância única `player`) é dono do único `AudioEngine`, fora do React. Ele expõe `subscribe`/`getSnapshot` (`{ sessionId, engine, error }`) para `useSyncExternalStore`.
- `useAudioEngine(sessionId)` (mixer) só se **conecta**: chama `player.open(sessionId)` e devolve o engine. **Não** dá `dispose` no unmount.
- O engine só é entregue depois de os 4 stems terem metadados (como antes).

### Quando o engine é solto
- **Fechar a barrinha** (`player.close()`): para, solta o wake lock e fecha o `AudioContext`.
- **Abrir outra sessão** (`player.open(outra)`): o engine anterior é descartado antes de carregar o novo. Abrir a mesma sessão reaproveita o engine, sem recarregar nem cortar.
- **Erro ao carregar os stems**: o engine é solto e o erro fica no snapshot; a barrinha se fecha.
- Recarregar a página/fechar a aba solta tudo, como qualquer `AudioContext`.
- Nunca há mais de um `AudioContext` aberto.

### Mix fora do mixer
- O mix só muda dentro do mixer. O engine guarda `setMix`/`setLoop`, então continua com o último mix ao sair da tela. O flush do save no unmount (0013) continua igual.
- Ao voltar, o `useMixer` carrega o mix salvo e reaplica o mesmo valor ao engine que já está tocando.

### Barrinha (mini player)
- `features/player/MiniPlayer`, montada no `AppLayout`, visível em toda tela **fora do mixer** (o mixer já tem o transporte). Mostra miniatura, título/artista, play/pause, fechar e progresso; tocar nela abre `/sessions/:id/mix`.
- O progresso usa `usePlayhead` (CSS var `--progress` por rAF), sem re-render a 60 fps.
- Medidas e estados em [docs/design/README.md](../design/README.md#mini-player-barrinha-de-reprodução-global).
- **Media Session** (título, artista, play/pause na tela de bloqueio e na notificação do Android) fica ligada ao player, inclusive dentro do mixer.
- O wake lock continua atrelado ao engine: a tela fica acesa enquanto toca, também navegando.

## Consequências
- A regra "`AudioContext` sempre fechado no unmount" do CLAUDE.md vira "fechado quando o player é fechado ou troca de música".
- Testes que montam o app precisam fechar o player entre si (`test/setup.ts` faz `player.close()` no `afterEach`).
- A fila de reprodução (#45) entra como evolução do `Player`: ele passa a ter mais de uma sessão, mas continua dono do único engine.

## Handoff (issue #44)
**Feito:** `Player`, `useAudioEngine` como cliente, `MiniPlayer` no `AppLayout`, Media Session, testes (`player.test.ts`, 4 casos no `MixerPage.test.tsx`), docs de design.

**Pegadinhas**
- `player` é singleton de módulo: teste que monta o app precisa começar com ele fechado (`test/setup.ts` já faz `player.close()`); teste de "recarregar a página" chama `player.close()` à mão.
- `useAudioEngine` devolve `engine: null` enquanto o snapshot é de outra sessão (o efeito de `open` ainda não rodou), então a view nunca ganha o engine da música anterior.
- A pílula de processamento sobe pelo `--player-offset`, definido em `.withBar` do `AppLayout`; ao mudar a altura da barrinha, mude lá e em `AppLayout.module.css` (padding do conteúdo).
- `--z-dock` passou de 20 para 21 e `--z-player` é 20 (pílula/dock ficam acima da barrinha, como no design).
- Não rode `prettier --write` em `frontend/src/api/` (arquivos gerados): reformata e o CI acusa drift do `gen:api`.

**Pendente / para a fila (#45):** conferência no celular (retrato/paisagem, safe area, tela de bloqueio) e a animação de saída da barrinha; o botão "próxima" tem lugar reservado no design.
