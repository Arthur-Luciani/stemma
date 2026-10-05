import { AudioEngine } from '../../audio/AudioEngine';
import { fakeAudio } from '../../test/audio';
import { DriftRecorder, percentile, summarize, type DriftSample } from './recorder';

const sample = (spread: number, drums = 0): DriftSample => ({
  t: 0,
  spread,
  drift: { vocals: 0, drums, bass: 0, other: 0 },
});

describe('resumo da medição', () => {
  it('percentil', () => {
    const values = Array.from({ length: 100 }, (_, i) => i + 1);
    expect(percentile(values, 95)).toBe(95);
    expect(percentile([], 95)).toBe(0);
  });

  it('espalhamento máximo, médio, p95 e leituras acima do limiar', () => {
    const summary = summarize([sample(10), sample(20, -35), sample(45)], 30);
    expect(summary.samples).toBe(3);
    expect(summary.spreadMs).toEqual({ max: 45, avg: 25, p95: 45 });
    expect(summary.maxDriftMs.drums).toBe(35);
    expect(summary.overThreshold).toBe(1);
  });

  it('sem leituras, tudo zero', () => {
    expect(summarize([], 30).spreadMs).toEqual({ max: 0, avg: 0, p95: 0 });
  });
});

describe('DriftRecorder', () => {
  it('stop é idempotente e solta a escuta do engine', () => {
    const engine = new AudioEngine(fakeAudio().options);
    const recorder = new DriftRecorder(engine);
    const first = recorder.stop();
    expect(recorder.stop()).toBe(first);
    engine.resync();
    expect(recorder.count).toBe(0);
    engine.dispose();
  });
});
