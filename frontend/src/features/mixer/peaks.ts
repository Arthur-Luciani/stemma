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
