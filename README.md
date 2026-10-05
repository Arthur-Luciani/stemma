# stemma

Separe qualquer música em voz, bateria, baixo e outros — e toque junto, do PC ou do celular.

App pessoal: busca no YouTube (yt-dlp) → separação com Demucs na GPU → mixer por stem (volume, pan, mute, solo, loop A–B, presets) → export do mixdown. Roda como serviço no PC e é acessado via Tailscale.

> Em construção. Plano e status: [docs/plan](docs/plan/README.md).

- [CLAUDE.md](CLAUDE.md) — arquitetura, regras e comandos
- [docs/design](docs/design/README.md) — marca, tokens e telas
- [docs/decisions](docs/decisions) — decisões de arquitetura
- [docs/SESSION_PROMPT.md](docs/SESSION_PROMPT.md) — prompt padrão para sessões do Claude Code
