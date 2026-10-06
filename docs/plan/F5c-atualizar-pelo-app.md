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
- [x] abordagem da tarefa agendada confirmada + ADR (tarefa SYSTEM + **instalador silencioso**, [ADR 0015](../decisions/0015-atualizar-pelo-app.md))
- [x] `GET/POST /api/system/update` com estado no banco
- [x] design da tela/aviso aprovado (chip + faixa + Dialog/Sheet, em Desvios)
- [x] aviso, confirmação e acompanhamento no app (desktop e celular)
- [x] falha mostra o motivo e mantém a versão anterior

## Critério de pronto
Com a versão N instalada pela F5b e a N+1 publicada: o celular mostra o aviso, "Atualizar" leva o PC à N+1 sem tocar no PC, e o app volta sozinho (com o "Recarregar" do PWA). Com falha simulada, o app mostra o erro e a N continua no ar. CI verde.

## Handoff
**Status:** implementada e ensaiada no PC em 2026-10-06. O critério de pronto **com releases de verdade** depende de duas releases que já tragam a F5c (v1.5.0 instalada pelo `.exe`, depois a v1.5.1). Isso fica para depois do merge e vai num PR `docs:`.

Ensaio no PC (o `stemma-ensaio` que tinha sobrado do PR #27, na v1.4.3, porta 8000 e 8443 do Tailscale; a instalação real, v1.4.1 na 8001, não foi tocada):
- **1.4.3 → 9.0.0 pelo `.exe` em modo silencioso** (`/VERYSILENT /NOTRAY /RESULTFILE=`): código 0, `ok|v9.0.0`. As tarefas `\Stemma\Atualizar-stemma-ensaio` e `Bandeja-stemma-ensaio` foram criadas, e o `UPDATE_TASK` foi gravado no `.env`. Isso mostra que uma instalação pré-F5c ganha as tarefas pelo `.exe`.
- **9.0.0 → 9.0.1 pelo app** (usuário clicando): chip, dialog com as novidades, "Atualizando…" e volta sozinho. Levou 30 s, gravou `succeeded` no banco e a bandeja foi reaberta pela tarefa `Bandeja`.
- **9.0.1 → 9.0.2 com falha simulada**: rollback (backup antes das migrations, banco restaurado) e o app mostrou "Não deu certo: A atualização para v9.0.2 falhou (A v9.0.2 não confirmou a versão no /health). A v9.0.1 continua no ar.". A falha também ficou gravada no banco. Isso cobre ainda a pendência do `/SIMULATEFAILURE` da F5b pelo `.exe`.
- Lista de releases falsa via `UPDATE_RELEASES_URL=file://…` e instalador local via `-InstallerPath` nos argumentos da tarefa (ver `docs/operacao.md`).

### Feito
- **Backend**:
  - `GET/POST /api/system/update` (`SystemUpdateService`, rotas finas);
  - tabela `system_updates` (migration 0003);
  - `pipeline/updater.py`: releases do GitHub por `urllib`, com `User-Agent`, timeout de 5 s, cache de 6 h (5 min na falha) e só releases com o instalador anexado. O disparo é `schtasks /run` pelo `run_process`;
  - CLI `update-result`;
  - recusas 409 (`update_running`, `jobs_active`, `update_unavailable`, `update_not_supported`), 503 sem GitHub e 502 se o `schtasks` falhar (grava `failed`);
  - um `running` com mais de 2 h vira `failed`;
  - notas do release-please em PT-BR, sem links e hashes, acumuladas entre a versão atual e a última.
- **Deploy**:
  - `Register-StemmaTasks` / `Unregister-StemmaTasks`. Install e Update do instalador recriam as tarefas antes de subir o serviço; o desinstalador remove;
  - `Invoke-StemmaAppUpdate` (`setup.ps1 -Mode AppUpdate`): baixa e confere o `.exe`, roda em modo silencioso, lê o `/RESULTFILE`, grava pelo CLI da release no ar e reabre a bandeja.
- **Instalador**: `/NOTRAY`, `/RESULTFILE=`, código de saída 1 na falha (`GetCustomSetupExitCode`), e o Tailscale fora do ar não trava a atualização silenciosa.
- **Frontend** (`features/update`):
  - chip na topbar (desktop) e faixa no Descobrir/Biblioteca (celular);
  - Dialog/BottomSheet em `?atualizacao=1`;
  - estados: atualizando (polling de 5 s que tolera o servidor fora), atualizado, falha com motivo, job ativo e instalação sem tarefa.
- **Testes**: pytest +27 (service, rotas, CLI, notas, `GitHubReleases`, `UpdateTask`); Pester 70 → 111 (tarefas, resultado do instalador, fluxo do `AppUpdate`); Vitest +13.
- **Docs**: ADR 0015, nota na ADR 0014, `operacao.md` (seção "Atualizar pelo app", layout, logs) e Desvios de design.

### Pendente
- **Critério real** (depois do merge): instalar a v1.5.0 pelo `.exe` na instalação real → publicar a v1.5.1 → aviso no celular → Atualizar → `/health` 1.5.1 e "Recarregar". A falha simulada já foi coberta no ensaio.
- **Ensaio que sobrou**: o `stemma-ensaio` está na v9.0.1, com `UPDATE_RELEASES_URL` no `.env` e a tarefa com `-InstallerPath … -SimulateFailure`. Para desligar: rodar o desinstalador "Stemma (stemma-ensaio)". Os dados ficam em `D:\stemma-ensaio-data`.
- Herdados: medição do AudioEngine no Android (F4a), branch protection (F0), iPhone (F5), ramos do Tailscale só no Pester (F5b).

### Decisões
- [ADR 0015](../decisions/0015-atualizar-pelo-app.md):
  - instalador silencioso (e não o `update.ps1`), escolhido com o usuário;
  - estado no banco: o backend grava `running` e o CLI grava o resultado;
  - cache em memória só da resposta do GitHub;
  - o "Recarregar" do PWA continua sendo o último passo.
- Desenho do aviso escolhido com o usuário: chip na topbar + faixa no celular + Dialog/Sheet (Desvios F5c em `docs/design`).
- `UPDATE_RELEASES_URL` (só ensaio) e `-InstallerPath` do `AppUpdate`, para ensaiar sem publicar release.

### Pegadinhas
- **O backend guarda a lista de releases por 6 h.** Uma release recém-publicada pode demorar a aparecer, e no ensaio é preciso reiniciar o serviço depois de mudar o `releases.json`.
- **Cada atualização recria as tarefas** (o instalador as registra de novo): ajustes feitos à mão na tarefa (como o `-InstallerPath` do ensaio) somem.
- **`New-ScheduledTaskPrincipal` com SID** (`S-1-5-18`, `S-1-5-32-545`) vira o nome localizado ("SISTEMA", "Usuários"). Nos testes, compare `LogonType`/`RunLevel`, e não o nome.
- **Pester 5 não está no Windows PowerShell do PC** (só o 3.4). Para rodar local sem instalar no perfil: baixe o `.nupkg` da PowerShell Gallery para uma pasta temporária e importe o `Pester.psd1` dela.
- **`python -m json.tool` no Git Bash** mostra acentos corrompidos (lê o stdin como cp1252). Os bytes da API estão certos.
- **Barras invertidas em scripts Python gerados pelo Bash tool**: sequências como `\a` e `\S` viraram escape do Python (um `\a` virou o byte BEL num `.md`). Para caminhos Windows, use `chr(92)`, e procure bytes de controle (o Pester já faz isso em `deploy/`).
- **Prioridade dos estados no app**: "atualizado agora há pouco" não pode esconder uma versão mais nova (bug achado no ensaio e corrigido).
