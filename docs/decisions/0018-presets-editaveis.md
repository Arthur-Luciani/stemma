# 0018 — Presets de mix editáveis, globais e com pan no match

- **Status:** aceita (2026-10-15)
- Muda a seção "Presets" da [0013](0013-estado-do-mixer.md); o resto da 0013 (estado na tela, save com debounce, loop A–B) continua valendo.
- Issue [#43](https://github.com/Arthur-Luciani/stemma/issues/43).

## Contexto
Os presets eram cinco fixos no código (enum `MixPreset` no backend, `PRESETS` no frontend), cada um só com mute e volume 100. Não dava para guardar um perfil de som próprio ("Bateria baixa") e reaplicá-lo em outra música.

## Decisão
- **Presets são dados do usuário**, globais (valem para qualquer música), na tabela `mix_presets`: `id`, `name` (único sem diferenciar caixa, até 40 caracteres), `position`, `visible` e `stems` (JSON `{stem: {volume, pan, mute}}`). Solo não entra: aplicar um preset limpa o solo. O loop A–B não faz parte do preset.
- **Tudo editável, inclusive os cinco de antes**: a migration 0005 os cria como presets comuns (Original, Sem voz, Sem bateria, Sem baixo, Só voz). Dá para renomear, alterar, reordenar, esconder e excluir qualquer um. Não há limite de presets.
- **Visibilidade no seletor**: o seletor mostra só os presets com `visible`, na ordem; os demais ficam atrás de um botão "Mais". O preset que o mix bate aparece sempre, mesmo escondido.
- **API**: `GET/POST /api/presets`, `PATCH/DELETE /api/presets/{id}`, `PUT /api/presets/order` (a lista completa de ids na nova ordem).
- **O preset continua derivado do mix** (princípio da 0013): `matchPreset` compara o mix com a lista do servidor, agora **incluindo o pan**, e sem solo. Vale o primeiro da ordem quando dois têm os mesmos níveis; nenhum bate → "Personalizado".
- **`mix_states.preset` sai**: o `PUT /mix` não recebe nem devolve mais o preset.
- **`exports.preset` vira o nome do preset (texto)**, um snapshot: o histórico e o nome do arquivo continuam mostrando o nome mesmo se o preset for renomeado ou excluído. O cliente manda o nome no `POST /exports`; sem ele, o export fica sem preset.
- O enum `MixPreset` deixa de existir.

## Migração
A 0005 cria a tabela com os cinco presets, converte os valores antigos de `exports.preset` no nome correspondente (`custom` vira "Personalizado", como a tela mostrava) e apaga `mix_states.preset`. Mixes e exports existentes continuam válidos. O downgrade recria o enum; nomes criados pelo usuário viram `custom`.

## Consequências
- Mudar os níveis de um preset muda quais mixes salvos aparecem como ele. O mix salvo não muda.
- Excluir todos os presets é permitido; o mix continua editável nos faders e aparece como "Personalizado".
- A tela de gerenciar (salvar, atualizar, renomear, reordenar, esconder, excluir) depende do desenho no Claude Design e vem depois da API e do seletor.
