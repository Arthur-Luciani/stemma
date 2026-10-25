# 0019 — Marca dos presets: ícone e cor

- **Status:** aceita (2026-10-16)
- Complementa a [0018](0018-presets-editaveis.md) (presets editáveis); o resto dela continua valendo.
- Issue [#62](https://github.com/Arthur-Luciani/stemma/issues/62).

## Contexto
No celular os nomes dos presets não cabem, e limitar caracteres não resolve: presets parecidos ("Aprendendo bateria", "Praticando bateria") só se diferenciam no fim do nome. A pesquisa da #62 mostrou que ícone sozinho se entende pior que texto, mas ícone ao lado do nome se acha mais rápido. Mesas digitais (as "scribble strips" do X32) identificam o canal com cor + nome + ícone.

## Decisão
- **Cada preset tem uma marca**, um quadradinho antes do nome, feita de `icon` e `color`, as duas opcionais. São colunas anuláveis em `mix_presets`. A marca é **só exibição**: não entra no match do preset com o mix.
- **Ícone**: um nome do Material Symbols de uma lista curta e fixa (`PresetIcon` em `domain/enums.py`). O app não aceita emoji: emoji muda de desenho entre Android e Windows e não segue os tokens.
- **Cor**: uma chave de uma paleta fixa (`PresetColor`): as 4 cores dos stems (`vocals`, `drums`, `bass`, `other`, que reaproveitam `--stem-*`) e 3 extras (`red`, `yellow`, `gray` em `--preset-*`). O banco guarda a chave, nunca hex. O dourado fica de fora, porque é o do preset ativo.
- **Sem ícone**, a marca mostra 4 barrinhas com o volume de cada stem do preset. **Sem cor**, a marca fica neutra.
- **O nome nunca some**: ele é o rótulo acessível do botão e aparece cortado com reticências onde falta espaço (pílulas, grade do Modo prática) e inteiro (até 2 linhas) na lista.
- **API**: `icon` e `color` em `PresetOut`, opcionais em `PresetCreate`. No `PATCH`, `null` remove e campo omitido não mexe. Valor fora da lista dá 422 (`validation_error`).
- **Presets padrão**: a migration 0006 dá ícone e cor aos cinco da 0005 que ainda têm o nome original e nenhuma marca: Original `graphic_eq` (sem cor), Sem voz `mic_off`/voz, Sem bateria `volume_off`/bateria, Sem baixo `volume_off`/baixo, Só voz `mic`/voz. O Material Symbols não tem ícone de bateria nem de baixo, então esses dois se diferenciam pela cor.
- **Edição**: o "Renomear" do gerenciador vira **Editar** (nome, ícone e cor) e usa o mesmo diálogo de salvar. A lista de ícones e cores do frontend (`features/mixer/presetMarkOptions.ts`) é conferida contra os tipos gerados do OpenAPI na compilação.

## Consequências
- Ícone ou cor novos = mudar o enum no backend, rodar `npm run gen:api` e incluir o valor na lista do frontend e nos nomes em `strings.ts` (a compilação acusa o que faltar).
- O downgrade da 0006 apaga as colunas, e com elas as marcas.
- Desenho da marca e do seletor de ícone e cor ainda não está no Claude Design; o que foi feito está em `docs/design/README.md` (seção "Feitos na #62").
