<p align="right"><strong>English</strong> · <a href="README.pt-BR.md">Português</a></p>

<p align="center">
  <img src="docs/assets/logo.svg" width="88" alt="">
</p>

<h1 align="center">stemma</h1>

<p align="center">
  <strong>Drop the vocals. Isolate the bass. Play along.</strong><br>
  Split any song into vocals, drums, bass and other with AI, right on your own PC,<br>
  and mix each part from your desktop or your phone.
</p>

<p align="center">
  <a href="https://github.com/Arthur-Luciani/stemma/releases/latest"><img src="https://img.shields.io/github/v/release/Arthur-Luciani/stemma?label=version&color=c18a3a" alt="Latest version"></a>
  <a href="https://github.com/Arthur-Luciani/stemma/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/Arthur-Luciani/stemma/ci.yml?branch=main&label=CI" alt="CI"></a>
  <img src="https://img.shields.io/badge/Windows-NVIDIA%20GPU-3fb896" alt="Windows with an NVIDIA GPU">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-6cb8f0" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://github.com/Arthur-Luciani/stemma/releases/latest"><strong>Download for Windows</strong></a>
  ·
  <a href="#how-it-works">How it works</a>
  ·
  <a href="#install">Install</a>
</p>

<p align="center">
  <img src="docs/assets/mixer-desktop.png" alt="Stemma's mixer on desktop: four lanes (vocals, drums, bass and other) with colored waveforms, the vocals muted by the No vocals preset and an A–B loop set between 1:03 and 1:34">
</p>

> The interface is in Brazilian Portuguese, so the screenshots are too.

## What it's for

- 🎤 **Sing over it**: the **No vocals** preset turns any song into karaoke.
- 🥁 **Take the band's place**: drop the drums, the bass or the guitar and play that part yourself.
- 🎧 **Learn by ear**: **solo** the bass, mark the tricky passage and repeat it in an **A–B loop** until you nail it.

## How it works

1. **Search.** Type the song's name or paste a YouTube link.
2. **Split.** [Demucs](https://github.com/facebookresearch/demucs) runs on your GPU and separates the song into 4 stems. A 5-minute song is ready in about a minute[^time].
3. **Play along.** Open the mixer, pick a preset or tweak each stem, and hit play.

## On your phone, too

Stemma runs on your PC and opens on your phone as an app (PWA), over HTTPS, through [Tailscale](https://tailscale.com/). No router ports to open, nothing exposed to the internet. To open it, point your camera at the QR code in the app or in the Windows tray icon.

<p align="center">
  <img src="docs/assets/celular-descobrir.png" width="250" alt="Discover screen on the phone: search field and a list to pick up where you left off">
  &nbsp;
  <img src="docs/assets/celular-mixer.png" width="250" alt="Mixer on the phone: presets as large buttons, an A–B loop and the play button">
  &nbsp;
  <img src="docs/assets/celular-ajustar.png" width="250" alt="Fine-tuning on the phone: fader, pan, mute and solo for each stem">
</p>

## Features

| Feature | What it does |
|---|---|
| 🎚️ **Per-stem mixer** | Volume, pan, mute and solo for vocals, drums, bass and other. |
| ⚡ **One-tap presets** | Original, No vocals, No drums, No bass and Vocals only. |
| 🔁 **A–B loop** | Repeat the passage you're practicing as many times as you like. |
| 💾 **Export** | Download your mix as MP3 or WAV. |
| 📚 **Library** | Search, filters, and every song's mix saved just the way you left it. |
| 📊 **Loudness** | LUFS and true peak for each song. |
| ⌨️ **Shortcuts** | On desktop: Space plays, 1–4 mute, ⇧1–4 solo, A/B set the loop. |
| 🔄 **Self-updating** | When a new version is out, the app tells you and updates itself, no trip to the PC needed. |

## Your PC, your music

Everything runs locally: the download, the separation and the mixer. No account, no subscription, and no audio ever goes to the cloud. On your phone, access is limited to your own devices, inside your Tailscale network.

## Install

**You'll need:** Windows 11, an NVIDIA graphics card with its driver installed, and about 6 GB of free space (plus ~50 MB per song). Stemma works without an NVIDIA GPU, but separation on the CPU is much slower.

1. Download `Stemma-Setup-vX.Y.Z.exe` from the [latest release](https://github.com/Arthur-Luciani/stemma/releases/latest).
2. Run it. The installer isn't code-signed, so Windows will warn you: click **More info → Run anyway**.
3. Choose where to keep your songs. The installer sorts out ports, HTTPS and Tailscale on its own and only asks when it needs you.
4. When it's done, click **Abrir o Stemma** (Open Stemma) or point your phone at the QR code.

To update, accept the new-version notice in the app or run the new version's installer. If an update fails, it rolls back to the previous version with your database intact. Details, rollback and logs are in [docs/operacao.md](docs/operacao.md) (in Portuguese).

## Built with

[Demucs](https://github.com/facebookresearch/demucs) (separation) · [yt-dlp](https://github.com/yt-dlp/yt-dlp) (download) · [FFmpeg](https://ffmpeg.org/) · [FastAPI](https://fastapi.tiangolo.com/) · [React](https://react.dev/) + [Vite](https://vite.dev/) · Web Audio API · [Tailscale](https://tailscale.com/)

## Responsible use

Stemma is meant for practice and personal use. Respect copyright and the terms of service of wherever your music comes from, and don't redistribute stems of copyrighted works.

## For developers

FastAPI + SQLite backend and a React + TypeScript frontend, served together by a single process that runs as a Windows service. To run it in development, see [docs/desenvolvimento.md](docs/desenvolvimento.md). Architecture, rules and commands are in [CLAUDE.md](CLAUDE.md), and architecture decisions in [docs/decisions](docs/decisions). The project docs are in Portuguese.

## License

[MIT](LICENSE) © Arthur Luciani

[^time]: Measured on the reference PC, with an NVIDIA GPU, download included.
