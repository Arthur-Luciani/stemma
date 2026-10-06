# 0015 — Atualizar pelo app: tarefa agendada + instalador silencioso

- **Status:** aceita (2026-10-06, F5c)
- Complementa a [ADR 0014](0014-instalador-e-conta-do-sistema.md) (instalador) e a [ADR 0003](0003-banco-como-verdade-e-fila.md) (banco como fonte da verdade).

## Contexto
Até a F5b, só dava para atualizar o Stemma rodando no PC o `.exe` da versão nova. O usuário quer ver no app (inclusive no celular) que existe versão nova e atualizar com um toque. O serviço não pode se atualizar de dentro: parar o serviço (WinSW) mata os processos filhos dele, inclusive o que estaria atualizando.

## Decisão
- **Quem atualiza é uma tarefa agendada do Windows**, `\Stemma\Atualizar`, sob demanda e como SYSTEM. Ela é criada pelo instalador (na instalação e na atualização) e removida pelo desinstalador. O backend só roda `schtasks /run /tn \Stemma\Atualizar` (binário e nome da tarefa vêm do `.env`: `SCHTASKS_BIN`, `UPDATE_TASK`). O processo da tarefa não é filho do serviço, então sobrevive à parada dele.
- **A tarefa roda o instalador da versão nova em modo silencioso**, e não o `update.ps1` da versão instalada. O instalador continua sendo o único caminho de atualização, e atualiza tudo junto: motor, catálogo de ferramentas, `Stemma.exe` da bandeja e a versão em "Adicionar ou remover programas". Fluxo (`setup.ps1 -Action AppUpdate` → `Invoke-StemmaAppUpdate`):
  1. consulta a última release do repositório e baixa `Stemma-Setup-vX.Y.Z.exe` + `.sha256` para `<raiz>\downloads`, conferindo o SHA256;
  2. roda `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOTRAY /RESULTFILE=… /LOG=…`. O instalador devolve código de saída ≠ 0 na falha e grava `ok|<versão>` ou `erro|<motivo>` no arquivo de resultado. O rollback automático é o da ADR 0007;
  3. grava o resultado no banco pelo CLI da release que ficou no ar (`python -m app.cli update-result`). Se deu certo, é a nova; se falhou, é a anterior, depois do rollback;
  4. reabre o ícone da bandeja na sessão de quem está logado, com a tarefa `\Stemma\Bandeja` (principal = grupo Usuários, interativa). Como SYSTEM, o instalador não consegue abrir janela na sessão do usuário (`/NOTRAY`).
- **Estado no banco** (tabela `system_updates`): o backend grava `running` ao disparar, e o CLI grava `succeeded`/`failed` com o motivo. Um `running` com mais de 30 minutos vira `failed` ("não terminou"), para o caso de o PC desligar no meio.
- **Consulta ao GitHub** (`GET /api/system/update`): a lista de releases (`/releases`, sem rascunhos e pré-releases), com `User-Agent`, timeout de 5 s e cache **em memória** de 6 h. Esse cache guarda só a resposta do GitHub (dado externo), não estado de job. Com falha, o resultado é `check: "unavailable"` (cacheado por 5 min), nunca 500. Só conta como novidade a release que já tem o instalador anexado (o job `installer` do `release.yml` termina minutos depois da release). As notas juntam as releases entre a versão atual e a última.
- **Recusas** (`POST`, 409): atualização em andamento, job ativo (processamento ou export: não interrompemos nada no meio) e "sem versão nova" ou "sem tarefa" (dev, CI ou instalação pelos scripts antigos).
- **Confiança**: a tarefa só baixa da Release do repositório configurado (`UPDATE_REPO`, padrão `Arthur-Luciani/stemma`) e confere o SHA256 publicado ao lado. É a mesma confiança de baixar o `.exe` à mão. Não há assinatura de código (ADR 0014).

## Alternativas descartadas
- **Rodar o `update.ps1` da versão instalada pela tarefa.** Seria mais simples, mas a bandeja, o desinstalador e a versão em "Adicionar ou remover" ficariam velhos, e o catálogo de ferramentas usado seria o da versão N.
- **Processo destacado iniciado pelo próprio serviço.** O WinSW mata a árvore de processos ao parar, e escapar disso depende de detalhes do job object.
- **Estado da atualização em arquivo ou memória.** Contraria a ADR 0003, e o backend reinicia no meio da atualização.

## Consequências
- O primeiro update pelo app só funciona a partir da versão que traz a F5c, instalada pelo `.exe`, porque é ele que cria a tarefa. Instalações antigas ganham a tarefa no próximo `.exe` rodado à mão.
- Log da atualização pelo app: `<raiz>\logs\update-vX.Y.Z.log` (Inno) e `<raiz>\logs\app-update.log` (tarefa).
- Teste de ponta a ponta só é possível com duas releases que já tragam a F5c.
