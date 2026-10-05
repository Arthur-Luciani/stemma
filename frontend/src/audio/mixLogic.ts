/**
 * Regras puras do AudioEngine (sem Web Audio): ganho efetivo, loop A–B e política de re-sync.
 * As leis de volume e mute/solo são as mesmas do mixdown do backend (ADR 0010).
 */

export interface StemControl {
  volume: number; // 0–100
  pan: number; // −1 a 1
  mute: boolean;
  solo: boolean;
}

/** Ganho linear de cada stem: com algum solo, só os solados; mute sempre tira; solado e mudo não conta. */
export function effectiveGains<K extends string>(
  stems: Readonly<Record<K, StemControl>>,
): Record<K, number> {
  const keys = Object.keys(stems) as K[];
  const anySolo = keys.some((k) => stems[k].solo && !stems[k].mute);
  const out = {} as Record<K, number>;
  for (const k of keys) {
    const s = stems[k];
    const audible = !s.mute && (!anySolo || s.solo);
    out[k] = audible ? Math.min(Math.max(s.volume, 0), 100) / 100 : 0;
  }
  return out;
}

export interface Loop {
  a: number;
  b: number;
}

/** Loop válido dentro da duração, ou `null` (precisa de A < B com pelo menos `minLength` s). */
export function normalizeLoop(
  a: number | null | undefined,
  b: number | null | undefined,
  duration: number,
  minLength = 0.1,
): Loop | null {
  if (a == null || b == null || !Number.isFinite(a) || !Number.isFinite(b)) return null;
  const lo = Math.max(0, Math.min(a, b));
  const hi = Math.min(duration, Math.max(a, b));
  return hi - lo >= minLength ? { a: lo, b: hi } : null;
}

/** Hora de voltar para A: a posição chegou ao B (ou passou dele). */
export function shouldWrapLoop(position: number, loop: Loop | null): boolean {
  return loop !== null && position >= loop.b;
}

export interface ResyncConfig {
  /** Acima disso (s), corrige. */
  threshold: number;
  /** Abaixo disso (s), a correção por velocidade termina. */
  settle: number;
  /** Até aqui (s), corrige mudando a velocidade; acima, faz seek. */
  maxNudge: number;
  /** Desvio de velocidade usado na correção (ex.: 0,02 = ±2%). */
  rateDelta: number;
}

export const DEFAULT_RESYNC: ResyncConfig = {
  threshold: 0.03,
  settle: 0.01,
  maxNudge: 0.15,
  rateDelta: 0.02,
};

export type ResyncAction = { kind: 'none' } | { kind: 'rate'; rate: number } | { kind: 'seek' };

/**
 * O que fazer com um stem cujo `drift = posição do stem − relógio mestre` (s).
 * `correcting` diz se ele já está em correção por velocidade (aí só para abaixo de `settle`).
 */
export function resyncAction(
  drift: number,
  correcting: boolean,
  cfg: ResyncConfig = DEFAULT_RESYNC,
): ResyncAction {
  const abs = Math.abs(drift);
  if (abs > cfg.maxNudge) return { kind: 'seek' };
  if (abs > cfg.threshold || (correcting && abs > cfg.settle)) {
    // Adiantado → mais devagar; atrasado → mais rápido.
    return { kind: 'rate', rate: drift > 0 ? 1 - cfg.rateDelta : 1 + cfg.rateDelta };
  }
  return correcting ? { kind: 'rate', rate: 1 } : { kind: 'none' };
}
