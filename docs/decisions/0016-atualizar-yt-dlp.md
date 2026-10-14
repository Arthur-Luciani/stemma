# 0016 — Atualizar o yt-dlp sozinho e pelo app

- **Status:** aceita (2026-10-14, issue #35)
- Complementa a [ADR 0015](0015-atualizar-pelo-app.md) (atualizar pelo app) e a [ADR 0003](0003-banco-como-verdade-e-fila.md) (banco como fonte da verdade).

## Contexto
O yt-dlp é a peça que mais quebra: o YouTube muda, a versão instalada para de baixar ou buscar, e o yt-dlp solta a correção em horas. Até aqui, atualizar exigia rodar `update.ps1 -YtDlpOnly` no PC como administrador. Pelo celular não havia o que fazer, e o problema só aparecia quando um job falhava. Além disso, a próxima atualização do Stemma voltava o yt-dlp para a versão do `uv.lock`.

Um botão fixo de "Atualizar yt-dlp" no app poluiria a interface com algo que quase nunca é usado.

## Decisão
- **A atualização é automática, diária.** A tarefa agendada `\Stemma\AtualizarYtDlp` (SYSTEM, criada e removida pelo instalador, como as da ADR 0015) roda todo dia às 5h, com `StartWhenAvailable` (PC desligado → roda quando ele ligar) e limite de 20 min. O app também a dispara (`schtasks /run`; `YTDLP_UPDATE_TASK` no `.env`). É uma tarefa à parte da `\Stemma\Atualizar` porque o `schtasks /run` não passa argumento.
- **Quem decide é o CLI, no banco.** No começo, a tarefa roda `python -m app.cli ytdlp-begin`:
  - com um pedido do app em andamento (`running`), devolve a versão gravada nele (a tarefa instala exatamente o que o app mostrou);
  - sem pedido (gatilho diário ou `-YtDlpOnly`), só segue sem atualização do Stemma em andamento, sem job na fila ou rodando e com versão nova no PyPI. Aí ele grava `running`, que trava jobs novos. Se não puder seguir, a tarefa termina sem mexer em nada (`skip|motivo`).
- **Instala com o serviço parado.** Para o serviço, roda `uv pip install yt-dlp[default]==<alvo>` no venv da release no ar, sobe e espera o `/health` com aquele yt-dlp. Com o serviço parado, nenhum `.pyd` dos extras fica travado, e a busca (que roda o yt-dlp dentro do processo) passa a usar a versão nova. Se falhar, reinstala a versão anterior e sobe de novo. O resultado vai para o banco (`ytdlp-result`).
- **Estado no banco**: a mesma tabela `system_updates`, com a coluna nova `component` (`app` ou `ytdlp`). Um `running` do yt-dlp com mais de 30 min vira `failed` ("não terminou"). Com qualquer atualização `running`, processar e exportar são recusados (409 `update_running`), e uma atualização recusa começar com a outra em andamento.
- **Versão nova**: `GET /api/system/ytdlp` compara a versão instalada (`yt_dlp.version`) com a última do PyPI (`https://pypi.org/pypi/yt-dlp/json`), com cache em memória de 1 h (5 min na falha). O cache é mais curto que o do GitHub (6 h) porque, quando o YouTube quebra, a correção sai rápido. As versões são comparadas como números (`2023.07.06` do pacote = `2023.7.6` do PyPI).
- **No app não há lugar fixo para o yt-dlp.** A ação aparece onde a falha aparece:
  - o card do job que falhou e o erro da busca mostram "Atualizar yt-dlp" quando o código de erro é típico de yt-dlp velho (`ytdlp_outdated`, `youtube_format_unavailable`) **e** existe versão nova. O botão só atualiza; o "Tentar de novo" de sempre reprocessa;
  - o aviso "yt-dlp desatualizado" (faixa no celular, chip no desktop) só aparece quando uma versão publicada há mais de 2 dias continua sem instalar, ou seja, quando a tarefa diária está falhando;
  - a versão instalada aparece numa linha discreta no sheet de atualização do Stemma.
- **Atualizar o Stemma não volta o yt-dlp.** Depois de criar o venv da release nova (serviço ainda no ar), o update compara o yt-dlp dela com o da release anterior e, se o anterior for mais novo, instala essa versão exata (`Sync-StemmaYtDlpFloor`). Se falhar, só avisa: a tarefa diária corrige. O rollback usa o venv da release anterior, que não muda.

## Alternativas descartadas
- **Botão "Atualizar yt-dlp" fixo (tela de sistema ou menu).** Pouco usado e polui o app. Com a atualização diária, ele quase nunca seria necessário.
- **Reprocessar sozinho depois de atualizar.** Exigiria guardar qual sessão reprocessar e disparar isso quando o serviço volta. O "Tentar de novo" que já existe resolve com um toque.
- **Modo novo na tarefa `\Stemma\Atualizar`.** O `schtasks /run` não passa argumento, e a tarefa precisaria descobrir pelo banco o que fazer. Uma tarefa por assunto fica mais simples e permite o gatilho diário só no yt-dlp.
- **`uv pip install --upgrade` com o serviço no ar.** Era o `-YtDlpOnly` antigo. Arrisca arquivo travado no Windows e instala "a última de agora", não a que o app mostrou.
- **Voltar sempre para a versão do `uv.lock` no update.** Desfaria a correção até a próxima rodada diária. O lock continua andando com as releases (Dependabot/Renovate, issue #36).

## Consequências
- A tarefa só existe em instalações feitas ou atualizadas pelo `.exe` a partir desta versão. Antes disso, `can_update` é `false` e o app não oferece a ação.
- O serviço fica fora do ar por ~30 s quando há yt-dlp novo, no máximo uma vez por dia, de madrugada (ou quando o usuário pede).
- Log da tarefa: `<raiz>\logs\ytdlp-update.log` (um arquivo só, que recomeça ao passar de 1 MB).
- Um yt-dlp novo pode quebrar algo que funcionava. O rollback automático cobre o caso de o serviço não subir, não o de um download específico piorar. Esse risco é aceito: no Stemma, o yt-dlp velho quebra muito mais do que o novo.
