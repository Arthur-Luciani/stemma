# stemma

Separe qualquer música em voz, bateria, baixo e outros — e toque junto, do PC ou do celular.

App pessoal: busca no YouTube (yt-dlp) → separação com Demucs na GPU → mixer por stem (volume, pan, mute, solo, loop A–B, presets) → export do mixdown. Roda como serviço no PC e é acessado via Tailscale.

> Em construção. Plano e status: [docs/plan](docs/plan/README.md).

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

Para separar áudio de verdade (GPU NVIDIA): `cd backend; uv sync --all-groups`. Comandos de teste e lint estão no [CLAUDE.md](CLAUDE.md#comandos).

## Documentação

- [CLAUDE.md](CLAUDE.md) — arquitetura, regras e comandos
- [docs/design](docs/design/README.md) — marca, tokens e telas
- [docs/decisions](docs/decisions) — decisões de arquitetura
- [docs/SESSION_PROMPT.md](docs/SESSION_PROMPT.md) — prompt padrão para sessões do Claude Code
