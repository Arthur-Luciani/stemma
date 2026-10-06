/**
 * Reamostra os peaks do backend (~1600 pontos, 0–1) para `count` barras.
 * Reduzindo, cada barra é o máximo do seu trecho (não perde transientes); ampliando, repete.
 */
export function resamplePeaks(peaks: readonly number[], count: number): number[] {
  if (count <= 0 || peaks.length === 0) return [];
  const out = new Array<number>(count);
  const ratio = peaks.length / count;
  for (let i = 0; i < count; i += 1) {
    const start = Math.floor(i * ratio);
    const end = Math.max(start + 1, Math.floor((i + 1) * ratio));
    let max = 0;
    for (let j = start; j < end && j < peaks.length; j += 1) max = Math.max(max, peaks[j] ?? 0);
    out[i] = Math.min(Math.max(max, 0), 1);
  }
  return out;
}

/**
 * Waveform única do mix (celular): soma dos peaks de cada stem × ganho efetivo, na escala
 * em que o mix com tudo em 100% enche a altura. Stem mudo ou baixo encolhe a forma.
 */
export function mixPeaks<K extends string>(
  peaks: Partial<Record<K, readonly number[]>>,
  gains: Readonly<Record<K, number>>,
): number[] {
  const stems = Object.keys(gains) as K[];
  const length = Math.max(0, ...stems.map((stem) => peaks[stem]?.length ?? 0));
  if (length === 0) return [];
  const resampled = stems.map((stem) => resamplePeaks(peaks[stem] ?? [], length));
  const full = new Array<number>(length).fill(0);
  const mixed = new Array<number>(length).fill(0);
  stems.forEach((stem, s) => {
    const row = resampled[s] ?? [];
    row.forEach((peak, i) => {
      full[i] = (full[i] ?? 0) + peak;
      mixed[i] = (mixed[i] ?? 0) + peak * gains[stem];
    });
  });
  const max = Math.max(...full);
  return max > 0 ? mixed.map((v) => Math.min(v / max, 1)) : mixed;
}
