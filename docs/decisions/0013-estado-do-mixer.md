# 0013 — Estado do mixer: preset derivado, tela como verdade e save com debounce

- **Status:** aceita (2026-10-05)
- Complementa a [0011](0011-frontend-dados-ao-vivo-e-url.md) (dados ao vivo e URL) e a [0012](0012-audio-engine-sincronia.md) (AudioEngine).

## Contexto
O mixer muda o mix muitas vezes por segundo: arrastar um fader gera dezenas de valores. O backend guarda um mix por sessão (`PUT /api/sessions/{id}/mix`), e o export sem `stems` usa esse mix salvo. O design pede o estado "Personalizado" assim que qualquer controle sai de um preset.

Os presets da v1 (vocal, bateria, karaokê) não correspondem aos da v2 (Original, Sem voz, Sem bateria, Sem baixo, Só voz).

## Decisão

### Presets
- Cada preset é **mute + volume 100**, decidido com o usuário:
  - Original = tudo em 100, sem mute;
  - "Sem X" = X mutado, o resto em 100;
  - "Só voz" = os outros três mutados.
- Aplicar um preset também volta o pan para C e limpa o solo. O loop A–B fica como está.
- **O preset não é um estado à parte: é derivado do mix** (`matchPreset`). Se o mix bate exatamente com um preset, é ele; se não, é "Personalizado". Por isso:
  - mexer em qualquer controle vira "Personalizado" sem código extra;
  - voltar o controle ao valor do preset volta a mostrar o preset;
  - o `preset` enviado no `PUT` é sempre o derivado. O que vem do servidor é ignorado na tela.

### Estado na tela
- Enquanto o mixer está aberto, **o estado local é a verdade** (`useMixer`, um por sessão). O mix chega uma vez pelo TanStack Query e um refetch não atropela o que está na tela.
- Cada mudança vai na hora para o `AudioEngine` (`setMix`/`setLoop`) e agenda um save.
- Isto não fere a regra "o banco é a fonte da verdade" do backend: é estado de edição de uma tela só (single-user), que é salvo logo em seguida.

### Persistência
- **Save com debounce de 600 ms**. O save lê o estado por `ref` no momento do envio, nunca de uma closure.
- Os saves entram numa fila (um de cada vez, na ordem), para o último sempre ganhar no servidor.
- Corpo igual ao último salvo/carregado não é reenviado.
- **Flush** imediato:
  - ao sair da tela (unmount);
  - no `pagehide` e no `visibilitychange` para `hidden`, com `fetch` `keepalive`, para o save sobreviver ao recarregar ou ao app ir para o fundo no celular;
  - antes de pedir um export, porque o backend exporta o mix salvo.
- Falha no save vira toast. O próximo save tenta de novo.

### Loop A–B
- Marcar A sem B deixa um "A pendente" só na tela, sem salvar. O loop salvo sempre tem os dois pontos (é o contrato da API).
- Mexer no loop por outro caminho (limpar, arrastar na timeline) descarta o A pendente.

## Consequências
- Recarregar a página (ou fechar a aba) logo depois de mexer não perde o mix.
- Duas abas no mesmo mix: a última a salvar ganha. Para um app single-user isso é aceitável.
- Mudar os níveis de um preset muda quais mixes antigos aparecem como esse preset. O mix salvo continua igual.
