/**
 * Estado do mixer (puro, sem React): presets, "Personalizado" derivado e o reducer da tela.
 * O preset nunca é guardado à parte: é sempre o que o mix atual bate (ou "custom").
 */

import type { MixPreset, MixState, MixStateIn, Stem, StemMix } from '../../api/types';
import { STEMS } from '../../audio/stems';

export type StemsMix = Record<Stem, StemMix>;

export interface MixerState {
  stems: StemsMix;
  /** Loop A–B em segundos, ou `null`. */
  loop: { a: number; b: number } | null;
}

export type PresetId = Exclude<MixPreset, 'custom'>;

/** Ordem de exibição dos presets. */
export const PRESETS: readonly PresetId[] = [
  'original',
  'no_vocals',
  'no_drums',
  'no_bass',
  'vocals_only',
];

/** Stems mudos em cada preset; os outros ficam em 100%, pan no centro e sem solo. */
const PRESET_MUTED: Record<PresetId, readonly Stem[]> = {
  original: [],
  no_vocals: ['vocals'],
  no_drums: ['drums'],
  no_bass: ['bass'],
  vocals_only: ['drums', 'bass', 'other'],
};

export const DEFAULT_STEM: StemMix = { volume: 100, pan: 0, mute: false, solo: false };

export function presetStems(preset: PresetId): StemsMix {
  const muted = PRESET_MUTED[preset];
  return Object.fromEntries(
    STEMS.map((stem) => [stem, { ...DEFAULT_STEM, mute: muted.includes(stem) }]),
  ) as StemsMix;
}

function sameStem(a: StemMix, b: StemMix): boolean {
  return a.volume === b.volume && a.pan === b.pan && a.mute === b.mute && a.solo === b.solo;
}

/** O preset que o mix bate exatamente, ou `custom`. */
export function matchPreset(stems: StemsMix): MixPreset {
  for (const preset of PRESETS) {
    const target = presetStems(preset);
    if (STEMS.every((stem) => sameStem(stems[stem], target[stem]))) return preset;
  }
  return 'custom';
}

/** Estado da tela a partir do que veio da API (stems faltando viram o padrão). */
export function fromServer(mix: MixState): MixerState {
  const stems = Object.fromEntries(
    STEMS.map((stem) => [stem, { ...DEFAULT_STEM, ...mix.stems[stem] }]),
  ) as StemsMix;
  const a = mix.loop_a_s ?? null;
  const b = mix.loop_b_s ?? null;
  return { stems, loop: a !== null && b !== null && a < b ? { a, b } : null };
}

/** Corpo do `PUT /mix`. O preset salvo é o derivado. */
export function toMixStateIn(state: MixerState): MixStateIn {
  return {
    stems: state.stems,
    preset: matchPreset(state.stems),
    loop_a_s: state.loop?.a ?? null,
    loop_b_s: state.loop?.b ?? null,
  };
}

const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max);

export type MixerAction =
  | { type: 'reset'; state: MixerState }
  | { type: 'volume'; stem: Stem; value: number }
  | { type: 'pan'; stem: Stem; value: number }
  | { type: 'mute'; stem: Stem; value?: boolean }
  | { type: 'solo'; stem: Stem; value?: boolean }
  | { type: 'preset'; preset: PresetId }
  | { type: 'loop'; loop: { a: number; b: number } | null };

function patchStem(state: MixerState, stem: Stem, patch: Partial<StemMix>): MixerState {
  return { ...state, stems: { ...state.stems, [stem]: { ...state.stems[stem], ...patch } } };
}

export function mixerReducer(state: MixerState, action: MixerAction): MixerState {
  switch (action.type) {
    case 'reset':
      return action.state;
    case 'volume':
      return patchStem(state, action.stem, { volume: Math.round(clamp(action.value, 0, 100)) });
    case 'pan':
      // Passo de 1%, igual ao rótulo (L30/R20).
      return patchStem(state, action.stem, { pan: Math.round(clamp(action.value, -1, 1) * 100) / 100 });
    case 'mute':
      return patchStem(state, action.stem, {
        mute: action.value ?? !state.stems[action.stem].mute,
      });
    case 'solo':
      return patchStem(state, action.stem, {
        solo: action.value ?? !state.stems[action.stem].solo,
      });
    case 'preset':
      return { ...state, stems: presetStems(action.preset) };
    case 'loop':
      return { ...state, loop: action.loop };
  }
}

/** Rótulo do pan: `C`, `L30`, `R20`. */
export function formatPan(pan: number): string {
  const pct = Math.round(Math.abs(pan) * 100);
  if (pct === 0) return 'C';
  return `${pan < 0 ? 'L' : 'R'}${pct}`;
}
