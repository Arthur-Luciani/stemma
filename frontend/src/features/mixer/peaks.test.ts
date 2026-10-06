import { mixPeaks, resamplePeaks } from './peaks';

describe('resamplePeaks', () => {
  it('reduz pegando o máximo de cada trecho', () => {
    expect(resamplePeaks([0.1, 0.9, 0.2, 0.3, 0.5, 0.4], 3)).toEqual([0.9, 0.3, 0.5]);
  });

  it('amplia repetindo os pontos', () => {
    expect(resamplePeaks([0.2, 0.8], 4)).toEqual([0.2, 0.2, 0.8, 0.8]);
  });

  it('limita a 0–1 e trata vazios', () => {
    expect(resamplePeaks([1.4, -0.2], 2)).toEqual([1, 0]);
    expect(resamplePeaks([], 10)).toEqual([]);
    expect(resamplePeaks([0.5], 0)).toEqual([]);
  });
});

describe('mixPeaks', () => {
  it('normaliza pelo mix cheio e encolhe com ganho menor ou mute', () => {
    const peaks = { vocals: [0.5, 1], drums: [0.5, 0] };
    expect(mixPeaks(peaks, { vocals: 1, drums: 1 })).toEqual([1, 1]);
    expect(mixPeaks(peaks, { vocals: 1, drums: 0 })).toEqual([0.5, 1]);
    expect(mixPeaks(peaks, { vocals: 0.5, drums: 0 })).toEqual([0.25, 0.5]);
  });

  it('peaks com tamanhos diferentes são reamostrados; sem peaks, vazio', () => {
    expect(mixPeaks({ vocals: [1, 1, 1, 1], drums: [1, 1] }, { vocals: 1, drums: 1 })).toHaveLength(
      4,
    );
    expect(mixPeaks({}, { vocals: 1 })).toEqual([]);
  });
});
