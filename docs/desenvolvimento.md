# Desenvolvimento

Como rodar o Stemma em dev. Arquitetura, regras e todos os comandos (teste, lint, release) estão no [CLAUDE.md](../CLAUDE.md).

## Rodar em dev

Pré-requisitos: [uv](https://docs.astral.sh/uv/), Node 22.12+ e FFmpeg no PATH. No Windows:

```powershell
copy .env.example .env      # opcional; tudo tem padrão
powershell -ExecutionPolicy Bypass -File scripts/dev.ps1
```

Sobe o backend em `http://127.0.0.1:8010` e o frontend em `http://127.0.0.1:5183`. Para abrir no celular via Tailscale:

```powershell
tailscale serve --bg --https=5183 http://127.0.0.1:5183
```

Para separar áudio de verdade (GPU NVIDIA): `cd backend; uv sync --all-groups`. Comandos de teste e lint estão no [CLAUDE.md](../CLAUDE.md#comandos).

## Documentação

- [CLAUDE.md](../CLAUDE.md): arquitetura, regras e comandos
- [docs/plan](plan/README.md): plano e status das fases
- [docs/design](design/README.md): marca, tokens e telas
- [docs/decisions](decisions): decisões de arquitetura
- [docs/operacao.md](operacao.md): instalar, atualizar e operar em produção
- [docs/SESSION_PROMPT.md](SESSION_PROMPT.md): prompt padrão para sessões do Claude Code

## Prints do README

Os prints em `docs/assets/` foram tirados do app em dev com o Chrome headless: desktop a 1440×900 e celular a 390×844 com escala 2 e emulação de toque.
