# Prompt padrão de sessão

Cole no início de **toda** sessão nova do Claude Code neste repo. Troque `<FASE>` pelo arquivo da fase (ex.: `F2a-fila-e-banco`).

---

```
Vamos trabalhar no Stemma.

1. Leia o CLAUDE.md, docs/plan/README.md e docs/plan/<FASE>.md (inclusive o Handoff das fases anteriores que ela referencia). Se a fase envolver UI, leia também docs/design/README.md e consulte o projeto do Claude Design citado lá.
2. Confira o estado real: git status, branch atual, último CI na main. Se algo divergir do que o plano diz, me avise antes de seguir.
3. Entre em plan mode e me apresente o plano da sessão: o que vai fazer, em que ordem, quais arquivos vai criar/alterar e como vai verificar cada item do critério de pronto. Liste antes tudo o que for transversal.
4. Depois que eu aprovar: crie uma branch, implemente com testes junto, rode lint/typecheck/testes localmente e mantenha o checklist da fase atualizado.
5. Antes do PR, rode /code-review e corrija o que for relevante.
6. Abra o PR (título em Conventional Commits) e acompanhe o CI até ficar verde.
7. No fim, preencha o Handoff da fase (feito, pendente, decisões, pegadinhas), atualize a tabela de status e crie ADR se alguma decisão de arquitetura mudou.

Regras: siga o CLAUDE.md à risca; não expanda o escopo além da fase sem me perguntar; se travar numa decisão que é minha, pergunte; se a sessão ficar longa demais, pare num ponto estável, faça o Handoff e me diga para abrir uma sessão nova.
```

---

## Variações

**Sessões paralelas (backend e frontend ao mesmo tempo)**: acrescente
`Trabalhe num git worktree próprio (EnterWorktree). Não altere arquivos fora de <backend/ ou frontend/> além do Handoff da sua fase.`

**Sessão curta de correção**: 
```
Leia o CLAUDE.md. Tarefa: <descrição>. Plan mode primeiro, depois branch + teste que reproduz o problema + correção + PR.
```
