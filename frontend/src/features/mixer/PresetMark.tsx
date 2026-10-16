import type { MixPreset } from '../../api/types';
import { STEMS, stemColorVar } from '../../audio/stems';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import { presetColorVar } from './presetMark';
import { presetLevel } from './presetText';
import styles from './PresetMark.module.css';

interface PresetMarkProps {
  preset: Pick<MixPreset, 'icon' | 'color' | 'stems'>;
  className?: string;
}

/**
 * Marca do preset (ADR 0019): o ícone, ou, sem ícone, 4 barrinhas com o volume de cada stem.
 * A cor tinge o quadrado; sem cor, ele fica neutro. Decorativa: o nome identifica o preset.
 */
export function PresetMark({ preset, className }: PresetMarkProps) {
  const color = preset.color ? presetColorVar(preset.color) : undefined;
  return (
    <span
      aria-hidden="true"
      className={cx(styles.mark, color && styles.tinted, className)}
      style={color ? ({ '--mark': color } as never) : undefined}
    >
      {preset.icon ? (
        <Icon name={preset.icon} size={18} filled />
      ) : (
        <span className={styles.bars}>
          {STEMS.map((stem) => {
            const { volume, mute } = presetLevel(preset.stems, stem);
            return (
              <span
                key={stem}
                className={cx(styles.bar, mute && styles.muted)}
                style={
                  {
                    '--stem': stemColorVar(stem),
                    height: mute ? undefined : `${String(Math.max(volume, 8))}%`,
                  } as never
                }
              />
            );
          })}
        </span>
      )}
    </span>
  );
}
