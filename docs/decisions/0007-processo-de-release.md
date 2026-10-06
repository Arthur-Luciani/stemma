# 0007 — Versionamento, CI e release

- **Status:** aceita (2026-10-05)

## Decisão
- **SemVer**, tags `vX.Y.Z`. Versão em `backend/pyproject.toml` (lida via `importlib.metadata`, exposta no `/health`) sincronizada com `frontend/package.json` pelo **release-please**.
- **Conventional Commits** + squash merge; título de PR validado por `amannn/action-semantic-pull-request`.
- **CI** (`ci.yml`, PR e push em `main`) em runners **GitHub-hosted Linux** (repo público = gratuito): backend `uv sync --group api --group dev` (nunca `pipeline`), ruff, mypy, pytest, smoke `alembic upgrade head`; frontend lint, typecheck, vitest, build; checagem de drift dos tipos OpenAPI. Branch protection exige CI verde.
- **Release** (`release.yml`): release-please mantém o PR de release (bump + `CHANGELOG.md`); ao mergear, cria tag + GitHub Release; um job anexa `stemma-vX.Y.Z.zip` + SHA256 (backend, migrations, `uv.lock`, `frontend/dist`, `deploy/`).
- **Atualização no PC** por `deploy/update.ps1` (pull, nunca push): baixa e verifica a release, extrai lado a lado em `releases\vX.Y.Z\`, `uv sync`, para o serviço, **backup do banco**, `alembic upgrade head`, troca a junction `current`, sobe e valida `/health`; rollback automático em falha. Mantém 3 releases. `-YtDlpOnly` atualiza só o yt-dlp.
- **Sem self-hosted runner**: num repo público, PRs de fork executariam código no PC.

## Atualização (F0, 2026-10-05)
A primeira release saiu **v1.0.0** (padrão do release-please quando não há tag anterior); mantida por decisão do usuário. A versão segue SemVer a partir daí.

## Atualização (F1, 2026-10-05)
Drift do OpenAPI sem subir servidor: `python -m app.openapi` grava o schema (chaves ordenadas, sem `info.version`) em `frontend/src/api/openapi.json`, e o `openapi-typescript` gera `src/api/schema.d.ts` a partir dele (`npm run gen:api` faz os dois). Ambos são commitados. No CI, o job `backend` regenera o JSON e o job `frontend` regenera os tipos; qualquer `git diff` faz o job falhar. Assim o job `frontend` não precisa de Python.

## Consequências
A GPU nunca é exercitada no CI → smoke manual pós-update (processar faixa curta, abrir mixer no celular, exportar).

## Atualização (F5, 2026-10-06)
- **Um venv por release** (`releases\vX.Y.Z\backend\.venv`) no lugar do `C:\stemma\venv` único. O `uv sync` roda antes de parar o serviço (no Windows, `.pyd` em uso fica travado) e o rollback só troca a junction `current`. O torch vem do cache do uv por hardlink, então o custo de disco é pequeno.
- **Backup e restauração** pelo próprio app: `python -m app.cli backup --dest` / `restore --src` (API de backup do SQLite, segura com WAL).
- **Rollback automático** (falha depois de parar o serviço): restaura o backup, volta o `current`, sobe a anterior e confere o `/health`. **Rollback manual** (`-Rollback`): backup + `alembic downgrade` até o head da release anterior, sem perder dados novos.
- `-SimulateFailure` força a falha do `/health` para testar o rollback. `-ZipPath` usa um pacote local.
- Funções do deploy em `deploy/StemmaDeploy.psm1`, testadas com Pester no job `deploy` do CI (pwsh no Linux; a junction só é testada no Windows).
- As releases até a v1.2.0 não têm `deploy/` no zip: o critério de pronto da F5 usa a primeira release com `deploy/` e a seguinte.

## Atualização (F5b, 2026-10-06)
- A release ganha `Stemma-Setup-vX.Y.Z.exe` + `.sha256`, gerados no job `installer` do `release.yml` (`windows-latest`, Inno Setup) com o `stemma-vX.Y.Z.zip` dentro. O empacotamento do zip foi para `scripts/package.sh`.
- Atualizar no PC = rodar o instalador da versão nova, que chama o mesmo fluxo do `update.ps1` (agora `Invoke-StemmaUpdate` no módulo). `/SIMULATEFAILURE` substitui o `-SimulateFailure` no teste do rollback.
- No CI, o Pester passou para o Windows PowerShell 5.1 (job `installer`, que também compila o instalador quando `deploy/`, `installer/` ou o empacotamento mudam). Ver [ADR 0014](0014-instalador-e-conta-do-sistema.md).
