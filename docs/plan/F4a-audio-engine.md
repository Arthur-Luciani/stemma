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
- [ ] AudioEngine completo
- [ ] waveform por peaks + playhead
- [ ] página /dev/engine
- [ ] medições no celular registradas no Handoff (números)
- [ ] ADR atualizada se houver fallback
- [ ] testes

## Critério de pronto
4 stems tocando sincronizados no celular por 3+ minutos, drift medido abaixo do limiar definido, sem crash; números registrados no Handoff; CI verde.

## Handoff
_Preencher ao final da sessão (inclua as medições)._
