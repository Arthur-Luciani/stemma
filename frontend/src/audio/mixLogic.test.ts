import {
  DEFAULT_RESYNC,
  effectiveGains,
  normalizeLoop,
  resyncAction,
  shouldWrapLoop,
  type StemControl,
} from './mixLogic';

const base: StemControl = { volume: 100, pan: 0, mute: false, solo: false };
const mix = (over: Partial<Record<'v' | 'd', Partial<StemControl>>> = {}) => ({
  v: { ...base, ...over.v },
  d: { ...base, ...over.d },
});

describe('effectiveGains', () => {
  it('usa volume/100 sem mute nem solo', () => {
    expect(effectiveGains(mix({ v: { volume: 50 } }))).toEqual({ v: 0.5, d: 1 });
  });

  it('mute tira o stem', () => {
    expect(effectiveGains(mix({ d: { mute: true } }))).toEqual({ v: 1, d: 0 });
  });

  it('com solo, só os solados tocam', () => {
    expect(effectiveGains(mix({ v: { solo: true } }))).toEqual({ v: 1, d: 0 });
  });

  it('solado e mudo não conta como solo', () => {
    expect(effectiveGains(mix({ v: { solo: true, mute: true } }))).toEqual({ v: 0, d: 1 });
  });
});

describe('loop', () => {
  it('ordena e limita à duração', () => {
    expect(normalizeLoop(30, 10, 20)).toEqual({ a: 10, b: 20 });
  });

  it('descarta loop incompleto ou curto demais', () => {
    expect(normalizeLoop(null, 5, 20)).toBeNull();
    expect(normalizeLoop(5, 5.05, 20)).toBeNull();
  });

  it('volta para A ao chegar no B', () => {
    const loop = { a: 1, b: 2 };
    expect(shouldWrapLoop(1.99, loop)).toBe(false);
    expect(shouldWrapLoop(2, loop)).toBe(true);
    expect(shouldWrapLoop(5, null)).toBe(false);
  });
});

describe('resyncAction', () => {
  it('não mexe abaixo do limiar', () => {
    expect(resyncAction(0.02, false)).toEqual({ kind: 'none' });
  });

  it('corrige pela velocidade entre o limiar e o máximo', () => {
    expect(resyncAction(0.05, false)).toEqual({ kind: 'rate', rate: 1 - DEFAULT_RESYNC.rateDelta });
    expect(resyncAction(-0.05, false)).toEqual({
      kind: 'rate',
      rate: 1 + DEFAULT_RESYNC.rateDelta,
    });
  });

  it('continua corrigindo até assentar e então volta a 1', () => {
    expect(resyncAction(0.02, true).kind).toBe('rate');
    expect(resyncAction(0.005, true)).toEqual({ kind: 'rate', rate: 1 });
  });

  it('faz seek acima do máximo', () => {
    expect(resyncAction(0.3, false)).toEqual({ kind: 'seek' });
  });
});
