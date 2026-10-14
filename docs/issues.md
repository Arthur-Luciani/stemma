# Issues

Como abrir e como ler as issues do Stemma. Vale para humanos e para o Claude Code.

## Quando abrir

- **Bug, melhoria ou ideia** que surgir do uso do app.
- **Dívida técnica**: melhoria interna, sem mudar o produto.
- Item fora do escopo descoberto **durante uma fase** continua indo para "Pendências descobertas" do Handoff ([plano](plan/README.md#convenções-de-todas-as-fases)). Se ele não couber em nenhuma fase planejada, vira issue, e o Handoff aponta para ela.

Antes de abrir, procure se já existe: `gh issue list --state all --search "<palavras>"`.

## Tipos e labels

Toda issue tem **exatamente um** label de tipo:

| Label | Quando | Template |
|---|---|---|
| `bug` | Algo que deveria funcionar e não funciona | [bug.md](../.github/ISSUE_TEMPLATE/bug.md) |
| `enhancement` | Recurso novo ou mudança de comportamento, já com proposta clara | [melhoria.md](../.github/ISSUE_TEMPLATE/melhoria.md) |
| `ideia` | Vontade ainda sem forma: precisa de investigação e decisões antes de virar implementação | [ideia.md](../.github/ISSUE_TEMPLATE/ideia.md) |
| `dívida técnica` | Melhoria interna sem mudar o produto | [divida-tecnica.md](../.github/ISSUE_TEMPLATE/divida-tecnica.md) |

Uma `ideia` não se implementa direto: o resultado dela é uma decisão (às vezes uma ADR) e uma ou mais issues `enhancement`, que são linkadas na ideia antes de fechá-la.

## Como escrever

- **Título** em PT-BR, dizendo o problema ou o resultado ("Pan não responde no mixer em retrato", "Presets de mix salvos pelo usuário"). Sem prefixo de Conventional Commits: ele vai no título do PR.
- **Corpo** segue o template do tipo. As seções fixas são:
  - **Problema** (ou **Motivação**): o que dói hoje, do ponto de vista de quem usa;
  - **Proposta**: o que fazer, no nível de comportamento e de onde mexe (camadas, arquivos, ADRs). Não é o plano de implementação;
  - **Cuidados**: regras do [CLAUDE.md](../CLAUDE.md), ADRs afetadas, migration, `gen:api`, celular, etc.;
  - **Em aberto**: decisões que são do usuário. Se a seção tem item, a issue **não está pronta para implementar**;
  - **Pronto quando**: critério verificável, inclusive os testes esperados.
- Aponte o código com caminho relativo (`frontend/src/features/mixer/PanControl.tsx`) e as ADRs com link. Hipóteses de causa vão marcadas como hipóteses.
- Bug do celular diz o aparelho, o navegador ou PWA e a orientação.
- Issue grande demais para um PR → divida em sub-issues ou vire uma fase em `docs/plan/` (quando precisar de mais de uma sessão).

Pelo terminal:

```bash
gh issue create --template bug.md            # abre o editor com o template
gh issue create --title "..." --label bug --body-file corpo.md
```

## Como ler (antes de implementar)

1. `gh issue view <n> --comments`: leia o corpo **e** os comentários. Um comentário pode mudar uma decisão do corpo.
2. **Em aberto** com item → pergunte ao usuário antes de planejar. A resposta vira comentário na issue (e o corpo é atualizado).
3. A issue é uma foto de quando foi escrita: confira se os arquivos, funções e ADRs citados ainda existem e se o problema ainda acontece. Divergência relevante → avise antes de seguir.
4. Leia as ADRs e as issues relacionadas que ela cita.
5. Siga o [prompt de sessão](SESSION_PROMPT.md#variações) (variação "a partir de uma issue"): plan mode, branch, testes, PR.
6. O PR leva `Closes #<n>` no corpo, para o merge fechar a issue. Se o PR resolver só parte, use `Refs #<n>` e diga o que falta.
7. Decisão tomada durante a implementação que muda a issue → comentário nela. Se for de arquitetura, também ADR.
