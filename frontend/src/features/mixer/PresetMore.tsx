import { useEffect, useRef, useState } from 'react';

import type { MixPreset } from '../../api/types';
import { strings } from '../../strings';
import { BottomSheet } from '../../ui/BottomSheet';
import { Button } from '../../ui/Button';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import { useIsDesktop } from '../../ui/useMediaQuery';
import { PresetMark } from './PresetMark';
import styles from './PresetMore.module.css';

interface PresetMoreProps {
  /** Presets fora do seletor. */
  hidden: readonly MixPreset[];
  active: MixPreset | null;
  onChange: (preset: MixPreset) => void;
  onSave?: () => void;
  onManage?: () => void;
  /** Botão grande do Modo prática. */
  large?: boolean;
}

/**
 * "Mais · N": os presets fora do seletor, mais Salvar e Gerenciar no rodapé. Popover ancorado
 * no desktop, bottom sheet no celular. Tocar num preset aplica e fecha.
 */
export function PresetMore({ hidden, active, onChange, onSave, onManage, large }: PresetMoreProps) {
  const [open, setOpen] = useState(false);
  const isDesktop = useIsDesktop();
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open || !isDesktop) return;
    const onPointer = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false);
    };
    document.addEventListener('pointerdown', onPointer);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('pointerdown', onPointer);
      document.removeEventListener('keydown', onKey);
    };
  }, [open, isDesktop]);

  const close = () => {
    setOpen(false);
  };

  const content = (
    <>
      {hidden.length > 0 && (
        <ul className={styles.list} aria-label={strings.mixer.preset.morePresets}>
          {hidden.map((preset) => {
            const checked = preset.id === active?.id;
            return (
              <li key={preset.id}>
                <button
                  type="button"
                  className={cx(styles.item, checked && styles.checked)}
                  aria-pressed={checked}
                  onClick={() => {
                    close();
                    onChange(preset);
                  }}
                >
                  <PresetMark preset={preset} />
                  <span className={styles.name}>{preset.name}</span>
                  {checked && <Icon name="check" size={18} />}
                </button>
              </li>
            );
          })}
        </ul>
      )}
      <div className={styles.footer}>
        {onSave && (
          <Button
            variant="secondary"
            size="sm"
            icon="bookmark_add"
            onClick={() => {
              close();
              onSave();
            }}
          >
            {strings.common.save}
          </Button>
        )}
        {onManage && (
          <Button
            variant="secondary"
            size="sm"
            icon="tune"
            onClick={() => {
              close();
              onManage();
            }}
          >
            {strings.mixer.preset.manageShort}
          </Button>
        )}
      </div>
    </>
  );

  return (
    <div ref={rootRef} className={styles.root}>
      <button
        type="button"
        className={cx(styles.trigger, large && styles.large, open && styles.open)}
        aria-label={strings.mixer.preset.morePresets}
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => {
          setOpen((v) => !v);
        }}
      >
        {strings.mixer.preset.more(hidden.length)}
        <Icon name="expand_more" size={18} />
      </button>
      {open &&
        (isDesktop ? (
          <div
            role="dialog"
            aria-label={strings.mixer.preset.morePresets}
            className={styles.popover}
          >
            {content}
          </div>
        ) : (
          <BottomSheet open onClose={close} label={strings.mixer.preset.morePresets}>
            {content}
          </BottomSheet>
        ))}
    </div>
  );
}
