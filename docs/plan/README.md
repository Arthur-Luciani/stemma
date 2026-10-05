# Plano — Stemma v2

Reescrita do `music-analyzer` sem o inspetor de bateria ([ADR 0001](../decisions/0001-repo-novo-e-escopo.md)). Cada fase (ou subfase) é executada numa **sessão nova** do Claude Code usando o [prompt padrão](../SESSION_PROMPT.md).

## Status

| Fase | Arquivo | Depende de | Status |
|---|---|---|---|
| F-1 Design | [docs/design](../design/README.md) | — | ✅ concluída (pendente: variação do mixer no celular, decidir até F4) |
| F0 Fundação | [F0-fundacao.md](F0-fundacao.md) | — | ✅ concluída — release v1.0.0 (pendente: teste no celular via Tailscale) |
| F1 Backend core | [F1-backend-core.md](F1-backend-core.md) | F0 | ✅ concluída — PR #5 (mergeado) |
| F2a Fila e eventos | [F2a-fila-e-eventos.md](F2a-fila-e-eventos.md) | F1 | ✅ concluída — PR #7 (mergeado) |
| F2b Pipeline de áudio | [F2b-pipeline-audio.md](F2b-pipeline-audio.md) | F2a | ✅ concluída — PR #8 (mergeado), release v1.1.0 |
| F3 Frontend: Descobrir, Processamento, Biblioteca | [F3-frontend-fluxos.md](F3-frontend-fluxos.md) | F0 (+ contrato da F1) | ⬜ próxima |
| F4a Protótipo do AudioEngine | [F4a-audio-engine.md](F4a-audio-engine.md) | F2b, F3 | ⬜ |
| F4b Mixer e Export | [F4b-mixer-export.md](F4b-mixer-export.md) | F4a | ⬜ |
| F5 Runtime, PWA e update | [F5-runtime-pwa.md](F5-runtime-pwa.md) | F4b | ⬜ |
| F6 Corte | [F6-corte.md](F6-corte.md) | F5 | ⬜ |

Legenda: ⬜ não iniciada · 🟡 em andamento · ✅ concluída · ⛔ bloqueada

## Paralelismo

```
F0 ──► F1 ──► F2a ──► F2b ──┐
  └──────────► F3 ──────────┴──► F4a ──► F4b ──► F5 ──► F6
```

Após a F1, a **F3 pode rodar em paralelo** com F2a/F2b em sessões separadas, cada uma no seu git worktree. O contrato entre elas é o OpenAPI (tipos gerados commitados; CI acusa drift). Na F3, estados de processamento podem ser simulados com o endpoint de dev da F2a ou com mocks do client.

## Convenções de todas as fases

- Toda fase termina com: checklist marcado, critério de pronto verificado, PR mergeado com CI verde, **Handoff** preenchido e esta tabela atualizada.
- Item fora do escopo descoberto durante a fase → anotar em "Pendências descobertas" do Handoff (ou no arquivo da fase futura correta), não implementar.
- Fase grande demais para uma sessão → parar num ponto estável, fazer Handoff parcial e continuar em sessão nova.

## Riscos acompanhados

| Risco | Onde é tratado |
|---|---|
| torch cu118 em Python 3.13 | F0 ([ADR 0008](../decisions/0008-python-e-deps.md)) |
| yt-dlp exigindo runtime JS e cookies | F2b + `/health` |
| Sincronia de 4 streams no celular | F4a ([ADR 0006](../decisions/0006-audio-no-celular.md)) |
| SQLite com worker em thread | F2a (WAL + busy_timeout) |
