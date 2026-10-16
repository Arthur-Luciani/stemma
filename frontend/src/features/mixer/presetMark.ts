import type { PresetColor, PresetIcon } from '../../api/types';

/** Ícones que o preset pode ter, na ordem da grade (iguais ao `PresetIcon` do backend). */
export const PRESET_ICONS = [
  'graphic_eq',
  'music_note',
  'mic',
  'mic_off',
  'record_voice_over',
  'volume_off',
  'volume_down',
  'hearing',
  'headphones',
  'piano',
  'lyrics',
  'school',
  'speed',
  'repeat',
  'star',
  'bolt',
] as const satisfies readonly PresetIcon[];

/** Cores que o preset pode ter (iguais ao `PresetColor` do backend). */
export const PRESET_COLORS = [
  'vocals',
  'drums',
  'bass',
  'other',
  'red',
  'yellow',
  'gray',
] as const satisfies readonly PresetColor[];

// Falham a compilação se o backend ganhar um valor que as listas não têm.
type Covers<All, Listed> = [Exclude<All, Listed>] extends [never] ? true : false;
type Assert<T extends true> = T;
export type IconsCovered = Assert<Covers<PresetIcon, (typeof PRESET_ICONS)[number]>>;
export type ColorsCovered = Assert<Covers<PresetColor, (typeof PRESET_COLORS)[number]>>;

const STEM_COLORS: ReadonlySet<PresetColor> = new Set(['vocals', 'drums', 'bass', 'other']);

/** Token da cor: as dos stems reaproveitam `--stem-*`; as extras são `--preset-*`. */
export function presetColorVar(color: PresetColor): string {
  return STEM_COLORS.has(color) ? `var(--stem-${color})` : `var(--preset-${color})`;
}
