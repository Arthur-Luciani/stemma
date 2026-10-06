# Design — Stemma

**Fonte da verdade visual:** projeto no Claude Design
https://claude.ai/design/p/e8a6b561-5c39-487b-8fb1-c0ff17dfed7b

| Arquivo no projeto | Conteúdo |
|---|---|
| `Stemma - Marca e Sistema.dc.html` | 3 caminhos de marca (1a Stemma ✅, 1b Desmix, 1c Quarteto), tokens, tipografia, espaçamento, componentes base, estados |
| `Stemma - Celular.dc.html` | Mixer em 4 variações (1d–1g) + fluxos M1–M6 |
| `Stemma - Desktop.dc.html` | Mixer, Descobrir e Biblioteca a 1440×900 |
| `uploads/design-briefing/` | Briefing e prints da v1 usados como entrada |

Este arquivo resume o que a implementação precisa. Em caso de dúvida visual, abra o projeto. Se a implementação divergir do design de propósito, registre aqui na seção **Desvios**.

## Marca

- Nome: **Stemma** (wordmark minúsculo `stemma`, Sora 600, letter-spacing −0.02em).
- Ícone: quadrado arredondado `bg-base` com borda `line` e **4 barras verticais** nas cores dos stems (Voz, Bateria, Baixo, Outros), alturas ≈ 46/84/62/30 de 160. Variantes 512/192 (PWA), 64, 32, 16 (favicon).
- Código de sessão: **`ST-###`** (ex.: `ST-042`), sempre em IBM Plex Mono.

## Tokens

### Cores (tema escuro, padrão)

| Token | Valor | Uso |
|---|---|---|
| `--bg-base` | `#121416` | fundo do app |
| `--bg-canvas` | `#0d0f11` | fundo externo / atrás do app |
| `--bg-surface` | `#1a1d21` | cards, lanes, painéis |
| `--bg-soft` | `#242931` | inputs, botões secundários, hover |
| `--bg-raised` | `#2c323b` | sheets, dialogs, popovers, toasts, dock |
| `--bg-raised-2` | `#3a414b` | item ativo dentro de raised, segmented ativo neutro |
| `--text-strong` | `#eceff3` | títulos, valores |
| `--text-body` | `#c2c8d0` | texto |
| `--text-muted` | `#9199a3` | rótulos, metadados |
| `--line` | `#323840` | bordas |
| `--line-strong` | `#4c5560` | bordas de controle, trilhos |
| `--accent` | `#c18a3a` | **uma** ação principal por tela: play, Separar, preset ativo, Baixar |
| `--accent-ink` | `#17120a` | texto sobre accent |
| `--accent-text` | `#eec07a` | texto/ícone em accent sobre fundo escuro |
| `--accent-soft` | `rgba(193,138,58,.16)` | fundo de chip/estado ativo âmbar |
| `--good` / `--good-text` / `--good-soft` | `#5ba17a` / `#8fd0aa` / `rgba(91,161,122,.16)` | pronta, sucesso |
| `--warn` / `--warn-text` / `--warn-soft` | `#bc9050` / `#e2b878` / `rgba(188,144,80,.16)` | processando |
| `--bad` / `--bad-text` / `--bad-soft` | `#ba6b78` / `#eaa6b1` / `rgba(186,107,120,.16)` | erro, excluir, mute ativo |
| `--bad-ink` | `#1d0f12` | texto sobre bad |
| `--solo` / `--solo-ink` | `#e3c46a` / `#1c1606` | solo ativo |

### Stems (paleta Okabe-Ito, segura para daltonismo)

| Stem | Token | Escuro | Claro |
|---|---|---|---|
| Voz | `--stem-vocals` | `#6cb8f0` | `#2f86c9` |
| Bateria | `--stem-drums` | `#e07a4f` | `#c4572b` |
| Baixo | `--stem-bass` | `#3fb896` | `#1f9373` |
| Outros | `--stem-other` | `#c98bd0` | `#9c5aa5` |

Stem mutado = cor a 30% de opacidade + waveform tracejada. A cor **sempre** acompanha o nome do stem.

### Tema claro (opcional, fase posterior)
`#f4f2ee` base · `#ffffff` surface · `#e8e5df` soft · `#1c1f23` text · `#5d636b` muted · `#a26d22` accent · stems na coluna "Claro".

### Tipografia
- **Sora** (UI) e **IBM Plex Mono** (tempo, código `ST-###`, métricas). Ícones: **Material Symbols Rounded**. Carregar via `<link>` com preconnect (ou self-host), nunca `@import`.
- Escala: display 32/600 (−0.02em) · title 20/600 · body 15/400 · label 13/500 · mono grande 28/500 · mono 13/400.
- Sem caixa alta em botões. Mono só para tempo, código e métricas.

### Espaçamento e raio
- Espaço: 4 · 8 · 12 · 16 · 24 · 32 · 48.
- Raio: 6 chip · 10 controle · 14 card · 22 sheet (topo) · 18 dialog.
- Alvo de toque mínimo: 44px.

## Componentes base (`frontend/src/ui/`)

| Componente | Especificação resumida |
|---|---|
| Button | 44px; variantes `primary` (accent), `secondary` (soft + borda), `ghost`, `danger` (borda bad), `icon` (44×44) |
| SegmentedControl | container surface + borda, itens 36px raio 9; ativo accent; estado "Personalizado" com borda tracejada accent e ponto |
| Fader | horizontal (trilho 6px, preenchimento na cor do stem, thumb 24px) e vertical (thumb 40×18); duplo toque volta a 100% |
| PanControl | desktop: slider centrado com marca no centro; celular: knob 44px (arrasto vertical); rótulo `C`, `L30`, `R20` |
| MuteSoloButton | 44×44 (32×32 no desktop); M ativo = bad, S ativo = solo |
| StatusChip | 26px raio 6 com ponto; Rascunho, Na fila · Nº, Baixando/Separando NN%, Pronta, Falhou |
| SessionCard / SessionRow | card (celular) e linha de tabela (desktop) com chip, ação principal e menu ⋯ |
| Toast | raised, ícone de estado, ação opcional ("Abrir") |
| Dialog | raised, raio 18; confirmação destrutiva com botão bad |
| BottomSheet | raised, raio 22 no topo, alça 40×5 |
| Menu | raised raio 12, itens 40px com ícone; destrutivo em bad-text, separado por divisória |
| ProcessingDock / ProcessingPill | desktop: dock recolhível canto inferior direito (nunca cobre o transport); celular: pílula acima da bottom nav que abre sheet |
| Skeleton, EmptyState, ErrorState | ver seção "Estados" do arquivo Marca e Sistema |

## Telas

### Desktop (1440×900)
- **Topbar** 60px: logo + `stemma`; navegação Descobrir · Biblioteca · Mixer (o Mixer é a última sessão aberta).
- **Mixer**: cabeçalho (título 26/600 + editar, artista · código · duração · data) e presets em segmented à direita. Transport em barra 64px: início, −5s, play 48px accent, +5s, tempo `1:12.4 / 3:41.0`, loop A–B (chip accent-soft com intervalo), LUFS/dBTP, botão **Exportar** que abre **popover** (formato WAV/MP3, progresso do export atual, lista "Anteriores" com Baixar). Régua de tempo. 4 lanes de 136px: cabeçalho 280px (ponto de cor, nome, M, S, Vol com %, Pan com valor) + waveform na cor do stem (parte já tocada opaca, restante a 35%). Região A–B destacada e playhead branco atravessando as lanes. Rodapé com dicas de atalho: `Espaço` play · `← →` 5s · `1–4` mute · `⇧1–4` solo · `A / B` marcar loop.
- **Descobrir**: "O que vamos separar hoje?", busca 60px com dica de colar link; lista de resultados (thumb 128×72 com duração, título, canal; selecionado com borda accent). À direita, card "Passo 2 de 2 · Confirme artista e título": artista com indicação "já usado · N sessões", título, texto "Vai entrar como ST-046, 2º na fila", botão Separar.
- **Biblioteca**: título + contagem, busca (`/` foca), filtros segmentados (Todas, Prontas, Em andamento · N, Rascunhos, Falhou), ordenação; tabela Código · Música · Estado · Duração · Criada · ações (ação principal contextual: Abrir mixer / Acompanhar / Continuar / Tentar de novo, + menu ⋯ com Editar artista e título, Reprocessar, Excluir…).
- **Dock de processamento** expandido: job atual com barra, etapa, % e ETA, Cancelar; fila com posição.

### Celular (390×844)
- **Navegação**: bottom nav com Descobrir, Biblioteca e Mixer (última sessão). A **pílula de processamento** flutua acima da nav em qualquer tela e abre o sheet.
- **M1 Descobrir vazio**: título, busca com botão colar, "Continuar de onde parou" (sessões recentes).
- **M2 Resultados**: lista tocável.
- **M3 Identidade**: bottom sheet com o vídeo escolhido, artista com autocomplete (artistas já usados + contagem), título, previsão "1 job na frente · pronto em ~2 min", botão Separar.
- **M4 Processamento**: sheet com etapas (Baixado → Separando 62% → Pronto), ETA, Cancelar; fila; job falho com Tentar de novo/Descartar; job pronto com Abrir mixer.
- **M5 Biblioteca**: busca, filtros, cards de sessão com chip e ⋯ (abre bottom sheet de ações).
- **M6 Exportar**: resumo da mixagem (preset, LUFS, níveis por stem), formato WAV / MP3 320, progresso, exports anteriores com tamanho e download.
- **Mixer** — 4 variações:
  - **1d Console vertical**: 4 channel strips com faders ~230px, pan como knob, M/S; waveform única do mix + transport embaixo.
  - **1e Lanes compactas**: faders horizontais quase da largura da tela, M/S sempre visíveis; toque no pan abre ajuste fino; transport em gaveta fixa na zona do polegar.
  - **1f Modo prática**: tempo 44px, play 104px, presets 72px, loop A–B arrastando na timeline; botão "Ajustar" abre o mixer fino.
  - **1g Paisagem**: console horizontal.

## Decisões pendentes

- [x] **Mixer no celular** (decidido na F4a, 2026-10-05): **1f (Modo prática) é a tela inicial do mixer**; "Ajustar" abre **1e (Lanes compactas)**; ao girar para paisagem, **1g**.

## Funcionalidades que o design adicionou ao escopo

Todas já refletidas nas fases (`docs/plan/`):
- Export em **WAV ou MP3 320**, com tamanho do arquivo e LUFS do export.
- **Loop A–B** (marcar com teclas A/B ou arrastando na timeline).
- Autocomplete de artista com **contagem de sessões** por artista.
- **Posição na fila e ETA** por job; **Cancelar** job; **Descartar** job falho.
- **Duração** da faixa na biblioteca e no mixer.
- Biblioteca com filtros por estado **com contagem** e ordenação.
- Atalhos de teclado (desktop).
- "Continuar de onde parou" (sessões recentes) no Descobrir.

## Desvios

Feitos na F3 (frontend fora do mixer), de propósito:

- **Sem "Vai entrar como ST-046"** no card de identidade do desktop. A API só gera o código no `POST /api/sessions`, e não há como prevê-lo antes. O card mostra só a previsão de fila, como o M3 do celular já fazia. O código aparece no toast "ST-046 entrou na fila".
- **Previsão de fila** é "N jobs na frente · começa em ~X" (X = maior ETA entre os jobs ativos) ou "Fila livre · começa agora", e não "pronto em ~2 min". O backend não estima a duração de um job que ainda não existe.
- **`/sessions/:id` (detalhe/acompanhar)** não tem tela no design. É uma página simples feita com peças existentes:
  - o cabeçalho do mixer (título, artista · `ST-###` · duração · data) + chip de estado;
  - o card de job do sheet M4 (etapas, ETA, Cancelar);
  - para rascunho, o formulário de identidade + Separar (é para onde aponta "Continuar"); para falha, a mensagem + Tentar de novo; para pronta, Abrir mixer.
- **"Duplicar"** saiu do menu ⋯ e do sheet de ações (decisão da F1).
- **Filtros no celular**: a pílula visível tem 36px, como no M5, mas o alvo de toque é de 44px.
- **Ordenação no celular**: o M5 não mostra ordenação. Ela aparece como um menu "Mais recentes ▾" abaixo dos filtros.
- **Logo no celular**: só aparece no Descobrir vazio (M1). As outras telas começam pelo título.
- **"Colar link"** é um botão (ícone + texto no desktop) no lugar da dica `⌘V`. No Windows o atalho seria Ctrl+V, e o botão funciona igual nos dois.

Feitos na F4b (mixer e export), de propósito:

- **Mixer no celular é tela cheia**: sem bottom nav e sem a pílula de processamento, como no 1e/1f/1g/M6. Para sair, use o "‹" do cabeçalho (ou o back do Android).
- **1e: ícone de editar no lugar do ⋯.** O menu só teria "Editar artista e título", então o atalho vai direto.
- **Desktop: botões A e B (e ×) ao lado do chip de loop.** O design só mostra o chip. Os botões deixam marcar o loop sem teclado. Arrastar nas lanes também marca o loop, como na timeline do celular.
- **1f: sem botões A/B.** O loop é marcado arrastando na waveform. Sem loop, o chip fica apagado e o texto ao lado ensina o gesto.
- **Export**: o formato começa em **MP3 320** (o design mostra WAV): é o arquivo mais leve para baixar no celular. O popover e o M6 ganharam um botão explícito "Exportar MP3 320". O design mostra só o seletor e o progresso.
- **LUFS/dBTP do transport e do resumo do M6 são do áudio original** (medidos no processamento). O LUFS da mixagem aparece em cada export pronto, na lista "Anteriores".
- **1g (paisagem)**: nome do stem numa linha e knob de pan com o valor na de baixo (no design ficam lado a lado e o nome não cabe). Os presets quebram linha em vez de rolar, para todos e o "Personalizado" ficarem à vista. Há uma linha de loop A–B (o design não tem) e a waveform ocupa o espaço livre.
- **Stem mudo no celular**: apaga nome, valor e fader, mas não os botões M/S (no design o card inteiro fica a 55%). Assim o M ativo continua legível.
- **Desktop = 900px de largura e 600px de altura.** O celular deitado fica no layout de celular (no mixer, o 1g), e não no desktop espremido. Abaixo de 1180px de largura, o transport do desktop esconde LUFS/dBTP.

Feitos na F5 (PWA), de propósito:

- **Ícone maskable** (`frontend/pwa/icon-maskable.svg`): fundo `--bg-base` cheio, sem a borda `line`, com as 4 barras na zona segura. O Android recorta no formato do launcher; a borda ficaria cortada. O ícone "any" (192/512) e o favicon são a marca com borda, como no design. O `apple-touch-icon` usa a versão maskable (o iOS não aceita transparência).
- **Splash do Android** = `background_color` `--bg-base` + ícone 512 + nome (gerada pelo Chrome a partir do manifest). Sem splash própria no iOS (exigiria uma imagem por tamanho de iPhone).
- **Modo app**: instalado, o app não seleciona texto ao segurar, não abre o menu do toque longo e não dá zoom com dois dedos. No navegador nada disso muda.


Feitos na F5b (instalador), de propósito:

- **"Abrir no celular" (só desktop)**: não há tela no design. É um botão só com ícone (`qr_code_2`, *ghost*) no canto direito da topbar, que abre um Dialog com o QR code do endereço atual, a dica de instalar o app e o endereço em mono. Se o app foi aberto por `localhost`/`127.0.0.1`, o Dialog explica que esse endereço só funciona no PC, em vez de mostrar um QR que não abre nada.
- **QR code escuro sobre claro** (`--qr-dark` = `--bg-base` sobre `--qr-light` = base do tema claro): a única área clara do app escuro. QR invertido (claro sobre escuro) falha em parte das câmeras.
- **Fora do app**: o ícone da bandeja do Windows (`installer/tray`) e as telas do instalador usam o ícone da marca e os controles nativos do Windows, sem os tokens.
