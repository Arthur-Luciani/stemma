import type { Stem } from '../../api/types';
import type { AudioEngine, EngineStats } from '../../audio/AudioEngine';
import { DEFAULT_RESYNC } from '../../audio/mixLogic';
import { STEMS } from '../../audio/stems';

/** Uma leitura de sincronia (a cada re-sync do engine, ~1 s). Tempos em ms. */
export interface DriftSample {
  t: number;
  spread: number;
  drift: Record<Stem, number>;
}

export interface DriftSummary {
  samples: number;
  spreadMs: { max: number; avg: number; p95: number };
  /** Maior |desvio| de cada stem em relação à mediana. */
  maxDriftMs: Record<Stem, number>;
  /** Leituras com espalhamento acima do limiar (antes da correção). */
  overThreshold: number;
}

const round = (n: number) => Math.round(n * 10) / 10;

export function percentile(values: readonly number[], p: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.max(0, index)] ?? 0;
}

export function summarize(samples: readonly DriftSample[], thresholdMs: number): DriftSummary {
  const spreads = samples.map((s) => s.spread);
  const maxDriftMs = Object.fromEntries(
    STEMS.map((stem) => [stem, round(Math.max(0, ...samples.map((s) => Math.abs(s.drift[stem]))))]),
  ) as Record<Stem, number>;
  return {
    samples: samples.length,
    spreadMs: {
      max: round(Math.max(0, ...spreads)),
      avg: round(spreads.length ? spreads.reduce((a, b) => a + b, 0) / spreads.length : 0),
      p95: round(percentile(spreads, 95)),
    },
    maxDriftMs,
    overThreshold: spreads.filter((s) => s > thresholdMs).length,
  };
}

/** `performance.memory` (só Chromium): heap JS em MB. Não inclui os buffers de mídia. */
export function heapMb(): number | null {
  const memory = (performance as Performance & { memory?: { usedJSHeapSize: number } }).memory;
  return memory ? round(memory.usedJSHeapSize / 1024 / 1024) : null;
}

export interface DriftReport {
  userAgent: string;
  startedAt: string;
  seconds: number;
  thresholdMs: number;
  summary: DriftSummary;
  rateCorrections: number;
  seekCorrections: number;
  stalls: number;
  hiddenCount: number;
  hiddenSeconds: number;
  heapMb: { start: number | null; end: number | null };
  contextState: string;
  baseLatencyMs: number;
}

/** Grava as leituras de sincronia de um engine até `stop()`. */
export class DriftRecorder {
  private readonly samples: DriftSample[] = [];
  private readonly startedAt = new Date();
  private readonly start = performance.now();
  private readonly heapStart = heapMb();
  private readonly base: EngineStats;
  private hiddenCount = 0;
  private hiddenSince: number | null = null;
  private hiddenMs = 0;
  private report: DriftReport | null = null;
  private readonly unsubscribe: () => void;

  constructor(private readonly engine: AudioEngine) {
    this.base = engine.stats;
    this.unsubscribe = engine.on('stats', (stats) => {
      if (engine.state !== 'playing') return;
      const drift = Object.fromEntries(STEMS.map((s) => [s, stats.drift[s] * 1000])) as Record<
        Stem,
        number
      >;
      this.samples.push({
        t: (performance.now() - this.start) / 1000,
        spread: stats.spread * 1000,
        drift,
      });
    });
    document.addEventListener('visibilitychange', this.onVisibility);
  }

  get elapsed(): number {
    return (performance.now() - this.start) / 1000;
  }

  get count(): number {
    return this.samples.length;
  }

  /** Para de gravar; chamadas seguintes devolvem o mesmo relatório. */
  stop(): DriftReport {
    if (this.report) return this.report;
    this.unsubscribe();
    document.removeEventListener('visibilitychange', this.onVisibility);
    if (this.hiddenSince !== null) this.hiddenMs += performance.now() - this.hiddenSince;
    const stats = this.engine.stats;
    const thresholdMs = DEFAULT_RESYNC.threshold * 1000;
    this.report = {
      userAgent: navigator.userAgent,
      startedAt: this.startedAt.toISOString(),
      seconds: round(this.elapsed),
      thresholdMs,
      summary: summarize(this.samples, thresholdMs),
      rateCorrections: stats.rateCorrections - this.base.rateCorrections,
      seekCorrections: stats.seekCorrections - this.base.seekCorrections,
      stalls: stats.stalls - this.base.stalls,
      hiddenCount: this.hiddenCount,
      hiddenSeconds: round(this.hiddenMs / 1000),
      heapMb: { start: this.heapStart, end: heapMb() },
      contextState: this.engine.contextState,
      baseLatencyMs: round(this.engine.baseLatency * 1000),
    };
    return this.report;
  }

  private readonly onVisibility = () => {
    if (document.visibilityState === 'hidden') {
      this.hiddenCount += 1;
      this.hiddenSince = performance.now();
    } else if (this.hiddenSince !== null) {
      this.hiddenMs += performance.now() - this.hiddenSince;
      this.hiddenSince = null;
    }
  };
}
