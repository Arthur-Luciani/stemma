import type { MixPreset } from '../../api/types';
import { STEMS } from '../../audio/stems';
import { strings } from '../../strings';
import type { PresetStem, Stem } from '../../api/types';
import { formatPan } from './mixState';
import { stemLabel } from './views';

/** Nível do stem no preset (o servidor sempre manda os 4; o padrão cobre o tipo). */
export function presetLevel(
  stems: Readonly<Record<string, PresetStem | undefined>>,
  stem: Stem,
): PresetStem {
  return { volume: 100, pan: 0, mute: false, ...stems[stem] };
}

/** O que o preset muda em relação ao "tudo em 100%, centro": `Bateria M · Baixo 80% L15`. */
export function presetDelta(preset: MixPreset): string {
  const parts: string[] = [];
  for (const stem of STEMS) {
    const { volume, pan, mute } = presetLevel(preset.stems, stem);
    if (mute) parts.push(`${stemLabel(stem)} M`);
    else if (volume !== 100 || pan !== 0) {
      const level = volume !== 100 ? ` ${String(volume)}%` : '';
      const side = pan !== 0 ? ` ${formatPan(pan)}` : '';
      parts.push(`${stemLabel(stem)}${level}${side}`);
    }
  }
  if (parts.length === 0) return strings.mixer.preset.allDefault;
  if (parts.length > 3) return `${parts.slice(0, 3).join(' · ')} +${String(parts.length - 3)}`;
  return parts.join(' · ');
}
