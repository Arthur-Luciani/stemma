import { resamplePeaks } from './peaks';

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
