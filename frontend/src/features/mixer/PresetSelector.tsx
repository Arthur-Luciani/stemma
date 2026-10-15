import { useRef, type KeyboardEvent } from 'react';

import type { MixPreset } from '../../api/types';
import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import { Menu } from '../../ui/Menu';
import styles from './PresetSelector.module.css';

interface PresetSelectorProps {
  presets: readonly MixPreset[];
  /** Preset derivado do mix; `null` = nenhum da lista ("Personalizado"). */
  value: MixPreset | null;
  onChange: (preset: MixPreset) => void;
  /**
   * `segmented`: desktop. `pills`: celular (1e e paisagem). `grid`: botões grandes do Modo
   * prática (1f), com "Personalizado" tracejado.
   */
  variant?: 'segmented' | 'pills' | 'grid';
  className?: string;
}

/**
 * Presets como grupo de rádio (setas do teclado). Só os marcados como visíveis aparecem; os
 * outros ficam atrás do "Mais" (e o ativo sempre aparece). "Personalizado" não se escolhe:
 * aparece quando o mix não bate com nenhum preset.
 */
export function PresetSelector({
  presets,
  value,
  onChange,
  variant = 'segmented',
  className,
}: PresetSelectorProps) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const custom = value === null;
  const shown = presets.filter((p) => p.visible || p.id === value?.id);
  const hidden = presets.filter((p) => !shown.includes(p));

  const onKeyDown = (event: KeyboardEvent, index: number) => {
    const delta = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
    if (delta === undefined) return;
    event.preventDefault();
    // As setas do grupo não são o ±5 s do mixer.
    event.stopPropagation();
    const next = (index + delta + shown.length) % shown.length;
    const preset = shown[next];
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
      {shown.map((preset, index) => {
        const checked = preset.id === value?.id;
        return (
          <button
            key={preset.id}
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
            <span>{preset.name}</span>
            {checked && variant === 'grid' && <Icon name="check" size={24} />}
          </button>
        );
      })}
      {hidden.length > 0 && (
        <Menu
          label={strings.mixer.preset.morePresets}
          triggerText={strings.mixer.preset.more}
          className={styles.more}
          items={hidden.map((preset) => ({
            label: preset.name,
            onSelect: () => {
              onChange(preset);
            },
          }))}
        />
      )}
      {(custom || variant === 'grid') && (
        <span className={cx(styles.custom, custom && styles.customActive)}>
          {custom && <span className={styles.dot} aria-hidden="true" />}
          {strings.mixer.preset.custom}
        </span>
      )}
    </div>
  );
}
