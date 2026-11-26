# Exploração de identidade visual (#66, #69)

Registro da sessão de 2026-11-25/26 que tentou dar uma cara própria ao app. **Nenhuma direção foi escolhida.** O próximo passo é uma sessão dedicada ao processo criativo (prompt no fim deste arquivo).

- Painel com todas as rodadas (Design artifact, privado): https://claude.ai/artifact/LepaQsZL2pTcuJckKy14u1
  - página **Exploração (A–D)**: territórios A, B, C e as variações do B (formas, telas, D);
  - página **Repaginada**: E, F, G e G2 (com tema escuro).
- Issues: #66 (ideia-mãe), #67 (navegação), #68 (movimento), #69 (identidade).
- O projeto antigo no Claude Design avulso (link no `README.md`) **fecha em 14/12/2026**. Exportar o que importar de lá antes disso.

## Contexto de uso (o que guia tudo)

- 90% do uso é **no celular, num suporte, enquanto o usuário toca bateria**: a ~1 m, com as baquetas na mão. Ele usa o app para tocar as músicas e praticar junto.
- Toca normalmente **com luz**, mas quer **tema escuro** também.
- A sala de ensaio atual é improvisada: **não serve de referência**.

## Gosto do usuário

- Discos: *Genesis* (1983), *Rage!* (Lettuce), *90125* (Yes), *Moanin'* (Art Blakey, 1959).
- Bandas: Genesis, Yes, Pink Floyd, America, Camel. Jazz: Miles Davis, Art Blakey, Clifford Brown.
- Não gosta de app genérico, "padrão, sem criatividade". **Também não gosta** quando a criatividade passa do ponto e **perde a praticidade**.
- Não tinha definições prévias de como o app deveria ser.

## Decisões que já valem (independem da identidade)

- **Navegação da #67**: a Biblioteca é a tela inicial; o botão **Adicionar** abre a busca/colar link; a aba Mixer sai.
- **A tela da música e o mixer viram uma só**: a música pronta abre direto no mixer; a que está processando mostra o progresso no mesmo lugar e vira o mixer ao terminar. (Ainda não está numa issue: entra na #67 ou numa nova.)
- **Tema claro e escuro.**
- **Não simplificar o que existe.** O usuário recusou: separar sem confirmar artista/título (fim do Rascunho), tirar filtros e ordenações, mover salvar/gerenciar presets para fora do modo prática, tirar o console em paisagem e juntar os avisos do topo. Tudo isso fica.
- As 4 cores dos stems continuam da paleta **Okabe-Ito** (daltonismo). Trocar de tom exige conferir contraste.

## O que cada rodada ensinou

| Rodada | O que era | Reação | Aprendizado |
|---|---|---|---|
| A · Blue Note | Tipografia condensada enorme, bloco de cor por música, réguas | Não escolhida | — |
| **B · Geometria 80** | Creme claro, tinta preta, linhas grossas, faixas diagonais dos stems | **Gostou**: "linhas bem marcadas e o app colorido com um creme bem claro" | Creme claro + linhas fortes + cor é um bom ponto de partida |
| C · Capa dupla | Noite verde-escura, serifa macia, rótulo de disco | Não escolhida | — |
| B + formas | Uma forma por stem (círculo, quadrado, triângulo, losango), X para "falhou" | No escuro "**ficou parecendo PlayStation**" | Círculo + quadrado + triângulo + X = controle do PlayStation. Evitar esse conjunto |
| D · Peças (Genesis 83) | Peças de brinquedo (círculo, bloco, arco, quarto de círculo) soltas | "**Ficou meio de criança**" | Formas como ícone/brinquedo infantilizam. Geometria precisa ser estrutura, não enfeite |
| E · Faixas | Suíço + capa anos 80; stems como faixas largas; tocar na faixa muta | Não escolhida | — |
| **F · Painel** | Visor escuro no topo, teclas grandes, LEDs, tecla de mute por canal, capa de medidores | "**Gostei, mas meio sem graça**"; depois: "**o mixer da F é bem mais legal que o nosso**" | A **estrutura** do mixer da F é a melhor até agora (ver abaixo) |
| G · Sala de controle 1983 | F + história: VU, fita crepe com marcador nos presets, contador de fita, carimbo do rolo (ST-###), teclas de gravador | "Até que gostei, mas algo não casou" | Faltava unidade: VU analógico, medidor de LED digital e UI chapada misturados; cores sem família |
| G2 | Uma luz âmbar para tudo que acende, stems com cor cheia de tampa de fader, painel bege, capa de faders; tema escuro completo | "**Ir para o lado de estúdio foi um erro**" | O tema de estúdio como fantasia não convenceu. Ficou literal demais |

### O que guardar do mixer da F (vale para qualquer estética)

- **Visor grande como protagonista** no topo: música, tempo grande, waveform e loop juntos.
- **Uma tecla por canal para mutar com um toque**, sem passar por preset nem pelo Ajustar. É o gesto mais útil para quem toca junto ("tira a bateria").
- **Teclas grandes** e bem separadas, com estado visível de longe (LED aceso ou apagado).
- O usuário notou que esse mixer "ficou muito fora do nosso padrão" (a estrutura atual: presets em grade → tempo → waveform → loop → transporte). Decidir se a estrutura do mixer muda faz parte da próxima sessão.

### Outras lições

- **Começamos pela pele, não pela ideia.** Cada rodada trocou cores, formas e fontes sem uma ideia condutora fixa. Por isso as direções ficavam plausíveis, mas nenhuma parecia inevitável.
- **As referências foram usadas só pelo nome.** Os protótipos saíram da memória dos discos, sem ver as capas. A próxima sessão precisa de **imagens reais** trazidas pelo usuário.
- **Uma metáfora literal vira fantasia** (estúdio, brinquedo). A identidade precisa de um motivo, mas que não seja uma fantasia.
- **Cores precisam de família**: poucas, com uma origem só. Misturar pastel de gráfico, cinza neutro, bege e laranja deixou tudo sem personalidade.
- O que não teve objeção: tempo grande em mono, linhas/teclas bem marcadas, capa gerada a partir dos stems (substitui a miniatura do YouTube), creme claro.

## Prompt da próxima sessão

```
Vamos fazer uma sessão dedicada ao processo criativo da identidade visual do Stemma (issues #66 e #69). Nada de código nesta sessão.

1. Leia o CLAUDE.md, docs/design/README.md e docs/design/exploracao-identidade.md (o registro da sessão anterior, com o que gostei e não gostei em cada rodada). Leia também o painel de protótipos citado lá com a ação "read" do Artifact (as duas páginas), principalmente F-Mixer e as linhas "Aprendizado".
2. Antes de desenhar qualquer coisa, conduza comigo, uma etapa por vez:
   a. Princípios de uso (3 a 5) que qualquer direção precisa respeitar, a partir do contexto: celular num suporte, a 1 m, tocando bateria.
   b. Núcleo da marca: palavras do que o app é e do que não é, e de 3 a 5 ideias condutoras de uma frase cada. Avalie cada ideia contra os princípios e me ajude a cortar.
   c. Referências reais: me peça imagens (capas, encartes, equipamentos, cartazes, apps de que gosto) e pergunte o que me pega em cada uma. Não use só o nome dos discos.
   d. Rodadas rápidas: para cada ideia que sobreviver, uma amostra pequena num Design artifact (fonte, família de cores e um componente, como o modo prática ou a tecla de mute por canal). Eu corto ou mantenho.
   e. Escolha com uma tabela de critérios (originalidade, praticidade a 1 m, se é a minha cara).
3. Leve em conta o que já está decidido no arquivo de exploração (navegação da #67, música e mixer juntos, tema claro e escuro, nada de simplificar o que existe) e a estrutura do mixer da F como referência de uso.
4. Só depois de escolhida a direção, monte as telas do celular (Biblioteca, Adicionar, música processando, mixer, Ajustar, barrinha) em claro e escuro, e me pergunte antes de seguir para o PC.
5. No fim, atualize docs/design/exploracao-identidade.md com o que foi decidido e o que ficou aberto, e me pergunte se abro PR `docs:`.

Regras: uma pergunta ou etapa por vez; quando eu disser só "gostei" ou "não gostei", pergunte o que exatamente; evite formas que lembrem o controle do PlayStation e formas de brinquedo; não proponha cortes de funcionalidade (já recusei); mobile-first, alvos ≥ 44px, contraste AA, cores dos stems da paleta Okabe-Ito.
```
