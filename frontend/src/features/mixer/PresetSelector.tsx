import { Fragment, useRef, type KeyboardEvent } from 'react';

import type { MixPreset } from '../../api/types';
import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import { Button } from '../../ui/Button';
import { PresetMore } from './PresetMore';
import styles from './PresetSelector.module.css';

interface PresetSelectorProps {
  presets: readonly MixPreset[];
  /** Preset derivado do mix; `null` = nenhum da lista ("Personalizado"). */
  value: MixPreset | null;
  onChange: (preset: MixPreset) => void;
  /** Abrem "Salvar como preset" e o gerenciador. Sem eles, os botões somem. */
  onSave?: () => void;
  onManage?: () => void;
  /**
   * `segmented`: desktop. `pills`: celular (1e e paisagem). `grid`: botões grandes do Modo
   * prática (1f), com "Personalizado" tracejado.
   */
  variant?: 'segmented' | 'pills' | 'grid';
  className?: string;
}

/**
 * Presets como grupo de rádio (setas do teclado). Só os marcados como visíveis aparecem; os
 * outros ficam no "Mais · N". O preset ativo escondido ocupa o 1º lugar, com o ícone de
 * escondido. "Personalizado" não se escolhe: aparece quando o mix não bate com nenhum preset.
 */
export function PresetSelector({
  presets,
  value,
  onChange,
  onSave,
  onManage,
  variant = 'segmented',
  className,
}: PresetSelectorProps) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const custom = value === null;
  const hidden = presets.filter((p) => !p.visible);
  const activeHidden = value && !value.visible ? value : null;
  const shown = [...(activeHidden ? [activeHidden] : []), ...presets.filter((p) => p.visible)];

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
    <div className={cx(styles.wrap, styles[`${variant}Wrap`], className)}>
      <div
        role="radiogroup"
        aria-label={strings.mixer.presets}
        className={cx(styles.group, styles[variant])}
      >
        {shown.map((preset, index) => {
          const checked = preset.id === value?.id;
          return (
            <Fragment key={preset.id}>
              <button
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
                {preset === activeHidden && (
                  <Icon
                    name="visibility_off"
                    size={18}
                    aria-label={strings.mixer.preset.hiddenActive}
                  />
                )}
                <span className={styles.label}>{preset.name}</span>
                {checked && variant === 'grid' && <Icon name="check" size={24} />}
              </button>
              {preset === activeHidden && <span className={styles.divider} aria-hidden="true" />}
            </Fragment>
          );
        })}
        {(custom || variant === 'grid') && (
          <span role="status" className={cx(styles.custom, custom && styles.customActive)}>
            {custom && <span className={styles.dot} aria-hidden="true" />}
            {strings.mixer.preset.custom}
          </span>
        )}
      </div>
      {presets.length === 0 && onSave && (
        <button type="button" className={styles.saveText} onClick={onSave}>
          <Icon name="bookmark_add" size={18} />
          {strings.mixer.preset.saveAs}
        </button>
      )}
      {presets.length > 0 && (
        <PresetMore
          hidden={hidden}
          active={value}
          onChange={onChange}
          onSave={onSave}
          onManage={onManage}
          large={variant === 'grid'}
        />
      )}
      {presets.length > 0 && onSave && variant !== 'grid' && (
        <Button
          variant="ghost"
          icon="bookmark_add"
          iconOnly
          label={strings.mixer.preset.save}
          onClick={onSave}
        />
      )}
    </div>
  );
}
