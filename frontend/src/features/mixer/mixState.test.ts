import {
  formatPan,
  fromServer,
  matchPreset,
  mixerReducer,
  presetStems,
  PRESETS,
  toMixStateIn,
  type MixerState,
} from './mixState';

const original = (): MixerState => ({ stems: presetStems('original'), loop: null });

describe('presets', () => {
  it('"Sem X" muta só o X e deixa o resto em 100%, centro e sem solo', () => {
    const stems = presetStems('no_drums');
    expect(stems.drums).toEqual({ volume: 100, pan: 0, mute: true, solo: false });
    expect(stems.vocals).toEqual({ volume: 100, pan: 0, mute: false, solo: false });
    expect(stems.bass.mute).toBe(false);
    expect(stems.other.mute).toBe(false);
  });

  it('"Só voz" muta os outros três', () => {
    const stems = presetStems('vocals_only');
    expect([stems.vocals.mute, stems.drums.mute, stems.bass.mute, stems.other.mute]).toEqual([
      false,
      true,
      true,
      true,
    ]);
  });

  it('cada preset se reconhece', () => {
    for (const preset of PRESETS) expect(matchPreset(presetStems(preset))).toBe(preset);
  });

  it('mudar qualquer controle vira Personalizado; voltar ao valor de antes volta ao preset', () => {
    let state = mixerReducer(original(), { type: 'preset', preset: 'no_vocals' });
    expect(matchPreset(state.stems)).toBe('no_vocals');

    for (const action of [
      { type: 'volume', stem: 'bass', value: 80 },
      { type: 'pan', stem: 'other', value: -0.3 },
      { type: 'solo', stem: 'drums' },
      { type: 'mute', stem: 'bass' },
    ] as const) {
      const changed = mixerReducer(state, action);
      expect(matchPreset(changed.stems)).toBe('custom');
    }

    state = mixerReducer(state, { type: 'volume', stem: 'bass', value: 80 });
    state = mixerReducer(state, { type: 'volume', stem: 'bass', value: 100 });
    expect(matchPreset(state.stems)).toBe('no_vocals');
    // Desmutar a voz no "Sem voz" é o Original.
    expect(matchPreset(mixerReducer(state, { type: 'mute', stem: 'vocals' }).stems)).toBe(
      'original',
    );
  });

  it('aplicar um preset limpa solo e pan, mas mantém o loop', () => {
    let state = mixerReducer(original(), { type: 'loop', loop: { a: 10, b: 20 } });
    state = mixerReducer(state, { type: 'solo', stem: 'bass' });
    state = mixerReducer(state, { type: 'pan', stem: 'bass', value: 0.5 });
    state = mixerReducer(state, { type: 'preset', preset: 'original' });
    expect(state.stems.bass).toEqual({ volume: 100, pan: 0, mute: false, solo: false });
    expect(state.loop).toEqual({ a: 10, b: 20 });
  });
});

describe('mixerReducer', () => {
  it('limita volume a 0–100 inteiro e pan a −1..1 em passos de 1%', () => {
    let state = mixerReducer(original(), { type: 'volume', stem: 'vocals', value: 140 });
    expect(state.stems.vocals.volume).toBe(100);
    state = mixerReducer(state, { type: 'volume', stem: 'vocals', value: 72.6 });
    expect(state.stems.vocals.volume).toBe(73);
    state = mixerReducer(state, { type: 'pan', stem: 'vocals', value: -3 });
    expect(state.stems.vocals.pan).toBe(-1);
    state = mixerReducer(state, { type: 'pan', stem: 'vocals', value: 0.123 });
    expect(state.stems.vocals.pan).toBe(0.12);
  });

  it('mute e solo alternam, ou recebem o valor explícito', () => {
    let state = mixerReducer(original(), { type: 'mute', stem: 'drums' });
    expect(state.stems.drums.mute).toBe(true);
    state = mixerReducer(state, { type: 'mute', stem: 'drums' });
    expect(state.stems.drums.mute).toBe(false);
    state = mixerReducer(state, { type: 'solo', stem: 'drums', value: true });
    state = mixerReducer(state, { type: 'solo', stem: 'drums', value: true });
    expect(state.stems.drums.solo).toBe(true);
  });
});

describe('ida e volta com a API', () => {
  it('fromServer completa stems faltando e ignora loop inválido', () => {
    const state = fromServer({
      stems: { vocals: { volume: 50, pan: 0, mute: false, solo: false } },
      preset: 'custom',
      loop_a_s: 30,
      loop_b_s: 10,
      updated_at: null,
    });
    expect(state.stems.vocals.volume).toBe(50);
    expect(state.stems.other).toEqual({ volume: 100, pan: 0, mute: false, solo: false });
    expect(state.loop).toBeNull();
  });

  it('toMixStateIn manda o preset derivado e o loop', () => {
    const state = mixerReducer(
      { stems: presetStems('no_bass'), loop: null },
      { type: 'loop', loop: { a: 58, b: 86 } },
    );
    expect(toMixStateIn(state)).toEqual({
      stems: presetStems('no_bass'),
      preset: 'no_bass',
      loop_a_s: 58,
      loop_b_s: 86,
    });
    expect(toMixStateIn(original()).loop_a_s).toBeNull();
  });
});

describe('formatPan', () => {
  it.each([
    [0, 'C'],
    [0.004, 'C'],
    [-0.3, 'L30'],
    [0.2, 'R20'],
    [-1, 'L100'],
  ])('%s → %s', (pan, label) => {
    expect(formatPan(pan)).toBe(label);
  });
});
