# F5c — Atualizar pelo app

## Objetivo
Saber de dentro do app (inclusive no celular) que existe versão nova do Stemma e atualizar com um toque, sem ir ao PC. Decidido com o usuário em 2026-10-06, junto da [F5b](F5b-instalador.md).

## Escopo
- **Backend** (service `system`, rotas finas):
  - `GET /api/system/update`: versão atual, última release no GitHub (consulta com cache de algumas horas, `User-Agent`, timeout) e se há novidade, com as notas da release (`CHANGELOG`). Falha de rede = "não foi possível verificar", nunca erro 500.
  - `POST /api/system/update`: dispara a atualização e responde na hora (202). Recusa se já houver uma em andamento ou se houver job processando (pergunta antes; não interrompe separação no meio).
  - Estado da atualização no banco (em andamento, concluída, falhou + mensagem), não em memória.
- **Quem atualiza**: o serviço não pode se atualizar de dentro, porque parar o serviço mata os filhos dele. Proposta: uma **tarefa agendada do Windows** (`\Stemma\Atualizar`, roda como SYSTEM, sob demanda), criada pela F5b, que roda o motor de update (`StemmaDeploy.psm1`). O backend só executa `schtasks /run`. Confirmar a abordagem no início e registrar em ADR.
- **Frontend**:
  - aviso discreto "Stemma vX.Y.Z disponível" com a ação "Ver" (não confundir com o "Nova versão disponível · Recarregar" do PWA, que aparece depois que o servidor já atualizou);
  - tela ou sheet com a versão atual → nova, as notas e o botão **Atualizar** (confirmação: "O Stemma fica fora do ar por ~1 min");
  - durante a atualização, o app perde o servidor: mostrar "Atualizando…" e reconectar sozinho (o `/ws` já reconecta), e no fim o toast do PWA pede para recarregar;
  - se falhar: mensagem com o motivo e "a versão anterior continua no ar".
- **Design**: não há tela para isso no Claude Design. Antes de implementar, desenhar no projeto (ou propor ao usuário uma variação com os componentes existentes: BottomSheet, Dialog, Toast) e registrar em Desvios.
- Testes: service (GitHub mockado, cache, recusa com job ativo, estados), rotas, UI (aviso, confirmação, atualizando/erro). Pester da tarefa agendada.

## Fora do escopo
Atualização automática sem toque; canal beta.

## Checklist
- [ ] abordagem da tarefa agendada confirmada + ADR
- [ ] `GET/POST /api/system/update` com estado no banco
- [ ] design da tela/aviso aprovado
- [ ] aviso, confirmação e acompanhamento no app (desktop e celular)
- [ ] falha mostra o motivo e mantém a versão anterior

## Critério de pronto
Com a versão N instalada pela F5b e a N+1 publicada: o celular mostra o aviso, "Atualizar" leva o PC à N+1 sem tocar no PC, e o app volta sozinho (com o "Recarregar" do PWA). Com falha simulada, o app mostra o erro e a N continua no ar. CI verde.

## Handoff
_Preencher ao final._
