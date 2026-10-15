import { makeDefaultPresets, makePreset } from '../../test/fixtures';
import type { MixPreset } from '../../api/types';
import {
  applyPreset,
  DEFAULT_STEM,
  effectiveVolume,
  formatPan,
  loopFromDrag,
  markA,
  markB,
  fromServer,
  matchPreset,
  mixerReducer,
  toMixStateIn,
  type MixerState,
} from './mixState';

const presets = makeDefaultPresets();
const byName = (name: string): MixPreset => {
  const found = presets.find((p) => p.name === name);
  if (!found) throw new Error(name);
  return found;
};
const original = (): MixerState => ({ stems: applyPreset(byName('Original')), loop: null });
const matchName = (state: MixerState) => matchPreset(state.stems, presets)?.name ?? null;

describe('presets', () => {
  it('aplicar usa volume, pan e mute do preset e limpa o solo', () => {
    const custom = makePreset('Bateria baixa', 5, { drums: { volume: 25, pan: -0.5 } });
    const stems = applyPreset(custom);
    expect(stems.drums).toEqual({ volume: 25, pan: -0.5, mute: false, solo: false });
    expect(stems.vocals).toEqual({ volume: 100, pan: 0, mute: false, solo: false });
  });

  it('"Sem X" muta só o X e "Só voz" muta os outros três', () => {
    expect(applyPreset(byName('Sem bateria')).drums.mute).toBe(true);
    expect(applyPreset(byName('Sem bateria')).bass.mute).toBe(false);
    const stems = applyPreset(byName('Só voz'));
    expect([stems.vocals.mute, stems.drums.mute, stems.bass.mute, stems.other.mute]).toEqual([
      false,
      true,
      true,
      true,
    ]);
  });

  it('cada preset se reconhece', () => {
    for (const preset of presets) expect(matchPreset(applyPreset(preset), presets)).toBe(preset);
  });

  it('o solo não conta e o volume tem tolerância de ±1', () => {
    const base = original();
    const solo = mixerReducer(base, { type: 'solo', stem: 'drums' });
    expect(matchName(solo)).toBe('Original');
    expect(matchName(mixerReducer(base, { type: 'volume', stem: 'bass', value: 99 }))).toBe(
      'Original',
    );
    expect(matchName(mixerReducer(base, { type: 'volume', stem: 'bass', value: 98 }))).toBeNull();
  });

  it('o pan entra no match', () => {
    const stems = { ...original().stems, bass: { ...DEFAULT_STEM, pan: 0.3 } };
    expect(matchPreset(stems, presets)).toBeNull();
  });

  it('com níveis iguais vale o primeiro da ordem; sem nenhum, é null', () => {
    const copy = makePreset('Cópia', 5);
    expect(matchPreset(original().stems, [copy, ...presets])?.name).toBe('Cópia');
    expect(matchPreset(original().stems, [])).toBeNull();
  });

  it('mudar qualquer controle vira Personalizado; voltar ao valor de antes volta ao preset', () => {
    let state = mixerReducer(original(), { type: 'preset', preset: byName('Sem voz') });
    expect(matchName(state)).toBe('Sem voz');

    for (const action of [
      { type: 'volume', stem: 'bass', value: 80 },
      { type: 'pan', stem: 'other', value: -0.3 },
      { type: 'mute', stem: 'bass' },
    ] as const) {
      expect(matchName(mixerReducer(state, action))).toBeNull();
    }

    state = mixerReducer(state, { type: 'volume', stem: 'bass', value: 80 });
    state = mixerReducer(state, { type: 'volume', stem: 'bass', value: 100 });
    expect(matchName(state)).toBe('Sem voz');
    // Desmutar a voz no "Sem voz" é o Original.
    expect(matchName(mixerReducer(state, { type: 'mute', stem: 'vocals' }))).toBe('Original');
  });

  it('aplicar um preset limpa solo e pan, mas mantém o loop', () => {
    let state = mixerReducer(original(), { type: 'loop', loop: { a: 10, b: 20 } });
    state = mixerReducer(state, { type: 'solo', stem: 'bass' });
    state = mixerReducer(state, { type: 'pan', stem: 'bass', value: 0.5 });
    state = mixerReducer(state, { type: 'preset', preset: byName('Original') });
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
      loop_a_s: 30,
      loop_b_s: 10,
      updated_at: null,
    });
    expect(state.stems.vocals.volume).toBe(50);
    expect(state.stems.other).toEqual({ volume: 100, pan: 0, mute: false, solo: false });
    expect(state.loop).toBeNull();
  });

  it('toMixStateIn manda os stems e o loop, sem preset', () => {
    const noBass = applyPreset(byName('Sem baixo'));
    const state = mixerReducer(
      { stems: noBass, loop: null },
      { type: 'loop', loop: { a: 58, b: 86 } },
    );
    expect(toMixStateIn(state)).toEqual({
      stems: noBass,
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

describe('marcar loop A–B', () => {
  it('A e depois B fecham o loop', () => {
    const first = markA(10, null);
    expect(first).toEqual({ loop: null, pendingA: 10 });
    expect(markB(20, first.loop, first.pendingA)).toEqual({
      loop: { a: 10, b: 20 },
      pendingA: null,
    });
  });

  it('A antes do B de um loop existente move o A; depois do B recomeça', () => {
    const loop = { a: 10, b: 20 };
    expect(markA(5, loop)).toEqual({ loop: { a: 5, b: 20 }, pendingA: null });
    expect(markA(25, loop)).toEqual({ loop: null, pendingA: 25 });
  });

  it('B sem A começa do início; B antes do A é ignorado', () => {
    expect(markB(8, null, null)).toEqual({ loop: { a: 0, b: 8 }, pendingA: null });
    expect(markB(9, { a: 10, b: 20 }, null)).toEqual({ loop: { a: 10, b: 20 }, pendingA: null });
    expect(markB(10.2, null, 10)).toEqual({ loop: null, pendingA: 10 });
  });

  it('arrasto vira loop em qualquer direção, se tiver o tamanho mínimo', () => {
    expect(loopFromDrag(30, 12)).toEqual({ a: 12, b: 30 });
    expect(loopFromDrag(12, 12.2)).toBeNull();
  });
});

describe('effectiveVolume', () => {
  it('é o volume, ou 0 se mudo ou fora do solo', () => {
    let stems = applyPreset(byName('Sem bateria'));
    expect(effectiveVolume(stems, 'drums')).toBe(0);
    expect(effectiveVolume(stems, 'vocals')).toBe(100);
    stems = mixerReducer({ stems, loop: null }, { type: 'solo', stem: 'bass' }).stems;
    expect(effectiveVolume(stems, 'vocals')).toBe(0);
    expect(effectiveVolume(stems, 'bass')).toBe(100);
  });
});
