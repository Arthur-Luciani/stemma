/**
 * Estado do mixer (puro, sem React): presets, "Personalizado" derivado e o reducer da tela.
 * O preset nunca é guardado à parte: é sempre o que o mix atual bate na lista do servidor (ou `null`).
 */

import type { MixPreset, MixState, MixStateIn, Stem, StemMix } from '../../api/types';
import { effectiveGains } from '../../audio/mixLogic';
import { STEMS } from '../../audio/stems';

export type StemsMix = Record<Stem, StemMix>;

export interface MixerState {
  stems: StemsMix;
  /** Loop A–B em segundos, ou `null`. */
  loop: { a: number; b: number } | null;
}

export const DEFAULT_STEM: StemMix = { volume: 100, pan: 0, mute: false, solo: false };

/** Aplica o preset: volume, pan e mute dele; o solo sempre sai. */
export function applyPreset(preset: MixPreset): StemsMix {
  return Object.fromEntries(
    STEMS.map((stem) => [stem, { ...DEFAULT_STEM, ...preset.stems[stem], solo: false }]),
  ) as StemsMix;
}

function matches(stems: StemsMix, preset: MixPreset): boolean {
  return STEMS.every((stem) => {
    const a = stems[stem];
    const b = { ...DEFAULT_STEM, ...preset.stems[stem] };
    // Volume com tolerância de ±1; pan e mute exatos; o solo não conta (ADR 0018).
    return Math.abs(a.volume - b.volume) <= 1 && a.pan === b.pan && a.mute === b.mute;
  });
}

/** O primeiro preset da lista (na ordem do usuário) que o mix bate, ou `null` (Personalizado). */
export function matchPreset(stems: StemsMix, presets: readonly MixPreset[]): MixPreset | null {
  return presets.find((preset) => matches(stems, preset)) ?? null;
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

/** Corpo do `PUT /mix`. O preset não vai: é derivado na tela. */
export function toMixStateIn(state: MixerState): MixStateIn {
  return {
    stems: state.stems,
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
  | { type: 'preset'; preset: MixPreset }
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
      return patchStem(state, action.stem, {
        pan: Math.round(clamp(action.value, -1, 1) * 100) / 100,
      });
    case 'mute':
      return patchStem(state, action.stem, {
        mute: action.value ?? !state.stems[action.stem].mute,
      });
    case 'solo':
      return patchStem(state, action.stem, {
        solo: action.value ?? !state.stems[action.stem].solo,
      });
    case 'preset':
      return { ...state, stems: applyPreset(action.preset) };
    case 'loop':
      return { ...state, loop: action.loop };
  }
}

/** Loop mais curto que isso (s) não vale. */
export const MIN_LOOP_S = 0.5;

type LoopRange = NonNullable<MixerState['loop']>;

export interface LoopMark {
  loop: LoopRange | null;
  /** A marcado esperando o B (só na tela, não é salvo). */
  pendingA: number | null;
}

/** Tecla/botão A: com um B à frente, move o A; senão o A fica esperando o B. */
export function markA(position: number, loop: LoopRange | null): LoopMark {
  if (loop && position < loop.b - MIN_LOOP_S)
    return { loop: { a: position, b: loop.b }, pendingA: null };
  return { loop: null, pendingA: position };
}

/** Tecla/botão B: fecha o loop a partir do A pendente (ou do A atual, ou do início). */
export function markB(position: number, loop: LoopRange | null, pendingA: number | null): LoopMark {
  const a = pendingA ?? loop?.a ?? 0;
  if (position > a + MIN_LOOP_S) return { loop: { a, b: position }, pendingA: null };
  return { loop, pendingA };
}

/** Arrasto na timeline (s, em qualquer ordem): loop se tiver o tamanho mínimo. */
export function loopFromDrag(from: number, to: number): LoopRange | null {
  const a = Math.max(0, Math.min(from, to));
  const b = Math.max(from, to);
  return b - a >= MIN_LOOP_S ? { a, b } : null;
}

/** Volume que sai de fato (0–100): mudo, ou fora de um solo, é 0. */
export function effectiveVolume(stems: StemsMix, stem: Stem): number {
  return Math.round(effectiveGains(stems)[stem] * 100);
}

/** Rótulo do pan: `C`, `L30`, `R20`. */
export function formatPan(pan: number): string {
  const pct = Math.round(Math.abs(pan) * 100);
  if (pct === 0) return 'C';
  return `${pan < 0 ? 'L' : 'R'}${String(pct)}`;
}
