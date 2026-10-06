import { useRef, type KeyboardEvent } from 'react';

import type { MixPreset } from '../../api/types';
import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import { PRESETS, type PresetId } from './mixState';
import styles from './PresetSelector.module.css';

interface PresetSelectorProps {
  /** Preset derivado do mix; `custom` = nenhum dos cinco. */
  value: MixPreset;
  onChange: (preset: PresetId) => void;
  /**
   * `segmented`: desktop. `pills`: celular (1e e paisagem). `grid`: botões grandes do Modo
   * prática (1f), com "Personalizado" tracejado.
   */
  variant?: 'segmented' | 'pills' | 'grid';
  className?: string;
}

/**
 * Presets como grupo de rádio (setas do teclado). "Personalizado" não se escolhe: aparece
 * quando o mix não bate com nenhum preset.
 */
export function PresetSelector({
  value,
  onChange,
  variant = 'segmented',
  className,
}: PresetSelectorProps) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const custom = value === 'custom';

  const onKeyDown = (event: KeyboardEvent, index: number) => {
    const delta = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
    if (delta === undefined) return;
    event.preventDefault();
    // As setas do grupo não são o ±5 s do mixer.
    event.stopPropagation();
    const next = (index + delta + PRESETS.length) % PRESETS.length;
    const preset = PRESETS[next];
    if (!preset) return;
    onChange(preset);
    refs.current[next]?.focus();
  };

  return (
    <div
      role="radiogroup"
      aria-label={strings.mixer.presets}
      className={cx(styles.group, styles[variant], className)}
    >
      {PRESETS.map((preset, index) => {
        const checked = preset === value;
        return (
          <button
            key={preset}
            ref={(el) => {
              refs.current[index] = el;
            }}
            type="button"
            role="radio"
            aria-checked={checked}
            // Sem preset ativo, o primeiro recebe o Tab.
            tabIndex={checked || (custom && index === 0) ? 0 : -1}
            className={cx(styles.item, checked && styles.active)}
            onClick={() => {
              onChange(preset);
            }}
            onKeyDown={(event) => {
              onKeyDown(event, index);
            }}
          >
            <span>{strings.mixer.preset[preset]}</span>
            {checked && variant === 'grid' && <Icon name="check" size={24} />}
          </button>
        );
      })}
      {(custom || variant === 'grid') && (
        <span className={cx(styles.custom, custom && styles.customActive)}>
          {custom && <span className={styles.dot} aria-hidden="true" />}
          {strings.mixer.preset.custom}
        </span>
      )}
    </div>
  );
}
