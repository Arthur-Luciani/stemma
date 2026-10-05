# 0001 — Repositório novo e escopo sem inspetor de bateria

- **Status:** aceita (2026-10-05)

## Contexto
A v1 (`music-analyzer`) acumulou o inspetor de bateria (ADTOF, classificador, MIDI/MusicXML, correções) e um catálogo de MIDI de mercado que não funcionam bem, além de problemas estruturais no backend e no frontend. O histórico git tem ~82 MB por causa de um checkpoint Demucs e de áudio commitados.

## Decisão
Reescrever como **Stemma** num repositório novo. Escopo: busca/download, separação em 4 stems, processamento ao vivo, biblioteca, mixer e export. Inspetor, catálogo MIDI e matching ficam de fora. Sessões da v1 **não** são migradas; a v1 é arquivada no corte (F6).

## Consequências
Histórico limpo e liberdade para corrigir a arquitetura. A v1 continua como referência de lógica (`docs/reference-v1.md`). Nenhum script de migração de dados.
