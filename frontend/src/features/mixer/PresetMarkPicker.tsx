import type { MixPreset, PresetColor, PresetIcon } from '../../api/types';
import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import { PRESET_COLORS, PRESET_ICONS, presetColorVar } from './presetMark';
import { PresetMark } from './PresetMark';
import styles from './PresetMarkPicker.module.css';

interface PresetMarkPickerProps {
  icon: PresetIcon | null;
  color: PresetColor | null;
  /** Níveis do preset: "Sem ícone" mostra as barrinhas deles. */
  stems: MixPreset['stems'];
  onIcon: (icon: PresetIcon | null) => void;
  onColor: (color: PresetColor | null) => void;
}

/** Escolha do ícone e da cor do preset (ADR 0019), como dois grupos de rádio nativos. */
export function PresetMarkPicker({ icon, color, stems, onIcon, onColor }: PresetMarkPickerProps) {
  const t = strings.mixer.preset;
  return (
    <>
      <fieldset className={styles.group}>
        <legend className={styles.legend}>{t.iconLabel}</legend>
        <div className={styles.icons}>
          <label className={styles.option} title={t.noIcon}>
            <input
              type="radio"
              name="preset-icon"
              className={styles.input}
              checked={icon === null}
              aria-label={t.noIcon}
              onChange={() => {
                onIcon(null);
              }}
            />
            <PresetMark preset={{ icon: null, color, stems }} />
          </label>
          {PRESET_ICONS.map((name) => (
            <label key={name} className={styles.option} title={t.iconNames[name]}>
              <input
                type="radio"
                name="preset-icon"
                className={styles.input}
                checked={icon === name}
                aria-label={t.iconNames[name]}
                onChange={() => {
                  onIcon(name);
                }}
              />
              <PresetMark preset={{ icon: name, color, stems }} />
            </label>
          ))}
        </div>
      </fieldset>
      <fieldset className={styles.group}>
        <legend className={styles.legend}>{t.colorLabel}</legend>
        <div className={styles.colors}>
          <label className={styles.option} title={t.noColor}>
            <input
              type="radio"
              name="preset-color"
              className={styles.input}
              checked={color === null}
              aria-label={t.noColor}
              onChange={() => {
                onColor(null);
              }}
            />
            <span className={cx(styles.swatch, styles.none)}>
              <Icon name="block" size={18} />
            </span>
          </label>
          {PRESET_COLORS.map((name) => (
            <label key={name} className={styles.option} title={t.colorNames[name]}>
              <input
                type="radio"
                name="preset-color"
                className={styles.input}
                checked={color === name}
                aria-label={t.colorNames[name]}
                onChange={() => {
                  onColor(name);
                }}
              />
              <span
                className={styles.swatch}
                style={{ '--swatch': presetColorVar(name) } as never}
              />
            </label>
          ))}
        </div>
      </fieldset>
    </>
  );
}
