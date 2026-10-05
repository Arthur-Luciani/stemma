import type { Stem } from '../api/types';
import { MasterClock } from './clock';
import {
  DEFAULT_RESYNC,
  effectiveGains,
  normalizeLoop,
  resyncAction,
  shouldWrapLoop,
  type Loop,
  type ResyncConfig,
  type StemControl,
} from './mixLogic';
import { STEMS } from './stems';

/**
 * Toca os 4 stems sincronizados, fora do React (ADR 0006 e 0012).
 *
 * Cada stem é um `<audio>` em streaming → `MediaElementSource → Gain → StereoPanner → destino`
 * (as mesmas leis do mixdown do backend, ADR 0010). O relógio mestre é o `AudioContext`; a cada
 * ~1 s o engine mede o desvio de cada stem em relação à mediana dos quatro e corrige quem passar
 * do limiar (velocidade levemente diferente para desvios pequenos, seek para os grandes).
 */

export type PlaybackState = 'idle' | 'loading' | 'paused' | 'playing' | 'buffering';

export interface EngineStats {
  /** Desvio de cada stem em relação à mediana dos quatro (s). */
  drift: Record<Stem, number>;
  /** Maior diferença entre dois stems (s). */
  spread: number;
  /** Relógio mestre − mediana dos stems (s). */
  clockOffset: number;
  /** Correções feitas desde o `load` (início de ajuste por velocidade e seeks). */
  rateCorrections: number;
  seekCorrections: number;
  /** Quantas vezes algum stem parou para carregar. */
  stalls: number;
}

export interface EngineEvents {
  state: PlaybackState;
  timeupdate: number;
  ended: undefined;
  error: { stem: Stem; message: string };
  stats: EngineStats;
}

type Listener<T> = (payload: T) => void;
type Listeners = { [K in keyof EngineEvents]: Set<Listener<EngineEvents[K]>> };

export interface EngineOptions {
  createContext?: () => AudioContext;
  createAudio?: () => HTMLAudioElement;
  resync?: ResyncConfig;
  /** Intervalo do laço de controle (loop A–B, fim, `timeupdate`). */
  tickMs?: number;
  resyncMs?: number;
  timeupdateMs?: number;
}

interface Channel {
  stem: Stem;
  el: HTMLAudioElement;
  source: MediaElementAudioSourceNode;
  gain: GainNode;
  pan: StereoPannerNode;
  control: StemControl;
  correcting: boolean;
  /** O próximo evento `pause` foi pedido pelo engine (os eventos de mídia chegam depois). */
  pausing: boolean;
  unlisten: () => void;
}

const HAVE_METADATA = 1;
const HAVE_FUTURE_DATA = 3;
/** Constante de tempo das rampas de ganho/pan (s): evita cliques ao mexer nos controles. */
const RAMP = 0.015;
/** Ao alinhar os stems depois de carregar, só faz seek em quem estiver mais longe que isso (s). */
const ALIGN_TOLERANCE = 0.03;
/** O relógio mestre é reancorado na mediana dos stems se se afastar mais que isso (s). */
const CLOCK_TOLERANCE = 0.05;

const defaultControl = (): StemControl => ({ volume: 100, pan: 0, mute: false, solo: false });

function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? (sorted[mid] ?? 0) : ((sorted[mid - 1] ?? 0) + (sorted[mid] ?? 0)) / 2;
}

const emptyDrift = (): Record<Stem, number> => ({ vocals: 0, drums: 0, bass: 0, other: 0 });

export class AudioEngine {
  private readonly ctx: AudioContext;
  private readonly channels: Channel[];
  private readonly clock: MasterClock;
  private readonly cfg: ResyncConfig;
  private readonly tickMs: number;
  private readonly resyncMs: number;
  private readonly timeupdateMs: number;
  private readonly listeners: Listeners = {
    state: new Set(),
    timeupdate: new Set(),
    ended: new Set(),
    error: new Set(),
    stats: new Set(),
  };

  private _state: PlaybackState = 'idle';
  private _duration = 0;
  private loop: Loop | null = null;
  private ticker: ReturnType<typeof setInterval> | null = null;
  private lastResync = 0;
  private lastTimeupdate = 0;
  private disposed = false;
  private _stats: EngineStats = {
    drift: emptyDrift(),
    spread: 0,
    clockOffset: 0,
    rateCorrections: 0,
    seekCorrections: 0,
    stalls: 0,
  };

  constructor(options: EngineOptions = {}) {
    this.ctx = (options.createContext ?? (() => new AudioContext()))();
    this.clock = new MasterClock(() => this.ctx.currentTime);
    this.cfg = options.resync ?? DEFAULT_RESYNC;
    this.tickMs = options.tickMs ?? 25;
    this.resyncMs = options.resyncMs ?? 1000;
    this.timeupdateMs = options.timeupdateMs ?? 250;

    // iOS: tocar mesmo com a chave de silencioso e continuar com a tela bloqueada.
    const nav = navigator as Navigator & { audioSession?: { type: string } };
    if (nav.audioSession) nav.audioSession.type = 'playback';

    const createAudio = options.createAudio ?? (() => new Audio());
    this.channels = STEMS.map((stem) => this.createChannel(stem, createAudio()));
    document.addEventListener('visibilitychange', this.onVisibilityChange);
  }

  // ---------------------------------------------------------------- leitura

  get state(): PlaybackState {
    return this._state;
  }

  get duration(): number {
    return this._duration;
  }

  get stats(): EngineStats {
    return this._stats;
  }

  get contextState(): string {
    return this.ctx.state;
  }

  get baseLatency(): number {
    return this.ctx.baseLatency;
  }

  /** Posição atual (s), barata o bastante para ler a cada quadro. */
  getPosition(): number {
    return Math.min(Math.max(this.clock.position, 0), this._duration || Infinity);
  }

  getLoop(): Loop | null {
    return this.loop;
  }

  on<K extends keyof EngineEvents>(event: K, listener: Listener<EngineEvents[K]>): () => void {
    const set = this.listeners[event] as Set<Listener<EngineEvents[K]>>;
    set.add(listener);
    return () => set.delete(listener);
  }

  // ---------------------------------------------------------------- carga

  /**
   * Aponta os `<audio>` para as URLs dos stems. Resolve quando todos têm metadados.
   * `duration` (dos peaks) vale até os metadados chegarem.
   */
  load(urls: Readonly<Record<Stem, string>>, duration = 0): Promise<void> {
    this.pauseElements();
    this.clock.stop();
    this.clock.seek(0);
    this._duration = duration;
    this._stats = { ...this._stats, rateCorrections: 0, seekCorrections: 0, stalls: 0 };
    this.setState('loading');
    for (const ch of this.channels) {
      ch.el.preload = 'auto';
      ch.el.src = urls[ch.stem];
      ch.el.load();
    }
    return new Promise((resolve, reject) => {
      const check = () => {
        if (this.disposed) return;
        if (!this.channels.every((ch) => ch.el.readyState >= HAVE_METADATA)) return;
        cleanup();
        const durations = this.channels.map((ch) => ch.el.duration).filter(Number.isFinite);
        if (durations.length) this._duration = Math.max(...durations);
        if (this._state === 'loading') this.setState('paused');
        resolve();
      };
      const fail = (event: Event) => {
        cleanup();
        const ch = this.channels.find((c) => c.el === event.target);
        reject(new Error(`Não foi possível carregar o stem ${ch?.stem ?? ''}.`.trim()));
      };
      const cleanup = () => {
        for (const ch of this.channels) {
          ch.el.removeEventListener('loadedmetadata', check);
          ch.el.removeEventListener('error', fail);
        }
      };
      for (const ch of this.channels) {
        ch.el.addEventListener('loadedmetadata', check);
        ch.el.addEventListener('error', fail);
      }
      check();
    });
  }

  // ---------------------------------------------------------------- transporte

  /** Tem que ser chamado no gesto do usuário: o `resume()` e os `play()` saem daqui, síncronos. */
  play(): void {
    if (this.disposed || this._state === 'playing' || this._state === 'buffering') return;
    if (this._state === 'idle' || this._state === 'loading') return;
    void this.ctx.resume();
    let position = this.clock.position;
    if (this._duration && position >= this._duration - 0.05) position = this.loop?.a ?? 0;
    this.alignTo(position, 0.01);
    this.clock.start(position);
    this.setState('playing');
    this.playElements();
    this.startTicker();
  }

  pause(): void {
    if (this._state !== 'playing' && this._state !== 'buffering') return;
    this.setState('paused');
    this.stopTicker();
    this.pauseElements();
    this.clock.stop();
    this.emit('timeupdate', this.getPosition());
  }

  toggle(): void {
    if (this._state === 'playing' || this._state === 'buffering') this.pause();
    else this.play();
  }

  seek(seconds: number): void {
    if (this.disposed) return;
    const max = this._duration || Infinity;
    const position = Math.min(Math.max(seconds, 0), max);
    this.clock.seek(position);
    this.alignTo(position, 0);
    this.emit('timeupdate', position);
  }

  // ---------------------------------------------------------------- mix

  setControl(stem: Stem, patch: Partial<StemControl>): void {
    const ch = this.channel(stem);
    ch.control = { ...ch.control, ...patch };
    this.applyMix();
  }

  setMix(stems: Readonly<Record<Stem, StemControl>>): void {
    for (const ch of this.channels) ch.control = { ...stems[ch.stem] };
    this.applyMix();
  }

  getControl(stem: Stem): StemControl {
    return { ...this.channel(stem).control };
  }

  /** Loop A–B; `null` em qualquer ponto (ou um intervalo inválido) desliga. */
  setLoop(a: number | null, b: number | null): Loop | null {
    this.loop = normalizeLoop(a, b, this._duration || Infinity);
    return this.loop;
  }

  // ---------------------------------------------------------------- fim

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.stopTicker();
    document.removeEventListener('visibilitychange', this.onVisibilityChange);
    for (const ch of this.channels) {
      ch.unlisten();
      ch.el.pause();
      ch.el.removeAttribute('src');
      ch.el.load();
      ch.source.disconnect();
      ch.gain.disconnect();
      ch.pan.disconnect();
    }
    for (const set of Object.values(this.listeners)) set.clear();
    void this.ctx.close().catch(() => undefined);
  }

  /** Mede e corrige o desvio agora (o laço faz isso sozinho a cada `resyncMs`). */
  resync(): EngineStats {
    const live = this.channels.filter((ch) => !ch.el.seeking);
    if (live.length === 0) return this._stats;
    const positions = live.map((ch) => ch.el.currentTime);
    const reference = median(positions);
    const drift = emptyDrift();
    let { rateCorrections, seekCorrections } = this._stats;

    for (const ch of live) {
      const d = ch.el.currentTime - reference;
      drift[ch.stem] = d;
      if (this._state !== 'playing') continue;
      const action = resyncAction(d, ch.correcting, this.cfg);
      if (action.kind === 'rate') {
        if (!ch.correcting && action.rate !== 1) rateCorrections += 1;
        ch.el.playbackRate = action.rate;
        ch.correcting = action.rate !== 1;
      } else if (action.kind === 'seek') {
        seekCorrections += 1;
        ch.el.playbackRate = 1;
        ch.correcting = false;
        ch.el.currentTime = reference;
      }
    }

    const clockOffset = this.clock.position - reference;
    if (this._state === 'playing' && Math.abs(clockOffset) > CLOCK_TOLERANCE)
      this.clock.seek(reference);

    this._stats = {
      ...this._stats,
      drift,
      spread: Math.max(...positions) - Math.min(...positions),
      clockOffset,
      rateCorrections,
      seekCorrections,
    };
    this.emit('stats', this._stats);
    return this._stats;
  }

  // ---------------------------------------------------------------- interno

  private createChannel(stem: Stem, el: HTMLAudioElement): Channel {
    const source = this.ctx.createMediaElementSource(el);
    const gain = this.ctx.createGain();
    const pan = this.ctx.createStereoPanner();
    source.connect(gain);
    gain.connect(pan);
    pan.connect(this.ctx.destination);
    const ch: Channel = {
      stem,
      el,
      source,
      gain,
      pan,
      control: defaultControl(),
      correcting: false,
      pausing: false,
      unlisten: () => undefined,
    };

    const onWaiting = () => {
      this.onStall();
    };
    const onReady = () => {
      this.onElementReady();
    };
    const onEnded = () => {
      this.onElementEnded();
    };
    const onPause = () => {
      if (ch.pausing) {
        ch.pausing = false;
        return;
      }
      // Pausa que não veio do engine (perda de foco de áudio, fone desconectado).
      if (this._state === 'playing' && !el.ended) this.pause();
    };
    const onError = () => {
      this.emit('error', { stem, message: el.error?.message || 'Falha ao tocar o stem.' });
    };
    // O `timeupdate` do `<audio>` continua com a aba em segundo plano, onde os timers são
    // estrangulados: garante o loop A–B e o fim com a tela bloqueada.
    const onTime = () => {
      if (this._state === 'playing') this.tick();
    };
    const events: [string, () => void][] = [
      ['waiting', onWaiting],
      ['canplay', onReady],
      ['canplaythrough', onReady],
      ['ended', onEnded],
      ['pause', onPause],
      ['error', onError],
    ];
    if (stem === STEMS[0]) events.push(['timeupdate', onTime]);
    for (const [name, fn] of events) el.addEventListener(name, fn);
    ch.unlisten = () => {
      for (const [name, fn] of events) el.removeEventListener(name, fn);
    };
    return ch;
  }

  private channel(stem: Stem): Channel {
    const ch = this.channels.find((c) => c.stem === stem);
    if (!ch) throw new Error(`Stem desconhecido: ${stem}`);
    return ch;
  }

  private applyMix(): void {
    const controls = Object.fromEntries(this.channels.map((ch) => [ch.stem, ch.control])) as Record<
      Stem,
      StemControl
    >;
    const gains = effectiveGains(controls);
    const now = this.ctx.currentTime;
    for (const ch of this.channels) {
      ch.gain.gain.setTargetAtTime(gains[ch.stem], now, RAMP);
      ch.pan.pan.setTargetAtTime(Math.min(Math.max(ch.control.pan, -1), 1), now, RAMP);
    }
  }

  private alignTo(position: number, tolerance: number): void {
    for (const ch of this.channels) {
      ch.el.playbackRate = 1;
      ch.correcting = false;
      if (Math.abs(ch.el.currentTime - position) > tolerance) ch.el.currentTime = position;
    }
  }

  private playElements(): void {
    for (const ch of this.channels) {
      ch.el.play().catch((error: unknown) => {
        if (error instanceof DOMException && error.name === 'AbortError') return;
        this.pause();
        const message =
          error instanceof DOMException && error.name === 'NotAllowedError'
            ? 'O navegador bloqueou o áudio. Toque em play de novo.'
            : 'Falha ao tocar o stem.';
        this.emit('error', { stem: ch.stem, message });
      });
    }
  }

  private pauseElements(): void {
    for (const ch of this.channels) {
      ch.el.playbackRate = 1;
      ch.correcting = false;
      if (!ch.el.paused) {
        ch.pausing = true;
        ch.el.pause();
      }
    }
  }

  /** Algum stem parou para carregar: pausa todos até todos terem dados. */
  private onStall(): void {
    if (this._state !== 'playing') return;
    this._stats = { ...this._stats, stalls: this._stats.stalls + 1 };
    this.setState('buffering');
    this.pauseElements();
    this.clock.stop();
  }

  private onElementReady(): void {
    if (this._state !== 'buffering') return;
    if (!this.channels.every((ch) => ch.el.readyState >= HAVE_FUTURE_DATA)) return;
    // Recomeça de onde o mais atrasado parou: voltar os outros usa dados já baixados.
    const position = Math.min(...this.channels.map((ch) => ch.el.currentTime));
    this.alignTo(position, ALIGN_TOLERANCE);
    this.clock.start(position);
    this.setState('playing');
    this.playElements();
  }

  private onElementEnded(): void {
    if (this._state !== 'playing') return;
    if (this.channels.some((ch) => ch.el.ended)) this.finish();
  }

  private finish(): void {
    this.setState('paused');
    this.stopTicker();
    this.pauseElements();
    this.clock.stop();
    if (this._duration) this.clock.seek(this._duration);
    this.emit('timeupdate', this.getPosition());
    this.emit('ended', undefined);
  }

  private readonly onVisibilityChange = () => {
    if (document.visibilityState !== 'visible') return;
    if (this._state !== 'playing' && this._state !== 'buffering') return;
    // iOS/Android podem suspender o contexto com a tela bloqueada.
    if (this.ctx.state !== 'running') void this.ctx.resume();
    if (this._state === 'playing' && this.channels.every((ch) => ch.el.paused)) {
      this.pause();
      return;
    }
    this.resync();
  };

  private startTicker(): void {
    this.stopTicker();
    this.lastResync = performance.now();
    this.ticker = setInterval(() => {
      this.tick();
    }, this.tickMs);
  }

  private stopTicker(): void {
    if (this.ticker !== null) clearInterval(this.ticker);
    this.ticker = null;
  }

  private tick(): void {
    if (this._state !== 'playing') return;
    const position = this.clock.position;
    if (shouldWrapLoop(position, this.loop) && this.loop) {
      this.seek(this.loop.a);
      return;
    }
    if (this._duration && position >= this._duration) {
      this.finish();
      return;
    }
    const now = performance.now();
    if (now - this.lastTimeupdate >= this.timeupdateMs) {
      this.lastTimeupdate = now;
      this.emit('timeupdate', position);
    }
    if (now - this.lastResync >= this.resyncMs) {
      this.lastResync = now;
      this.resync();
    }
  }

  private setState(state: PlaybackState): void {
    if (state === this._state) return;
    this._state = state;
    this.emit('state', state);
  }

  private emit<K extends keyof EngineEvents>(event: K, payload: EngineEvents[K]): void {
    for (const listener of this.listeners[event] as Set<Listener<EngineEvents[K]>>)
      listener(payload);
  }
}
