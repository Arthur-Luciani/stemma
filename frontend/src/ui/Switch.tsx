import type { ButtonHTMLAttributes } from 'react';

import { cx } from './cx';
import styles from './Switch.module.css';

interface SwitchProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onChange'> {
  checked: boolean;
  onChange: (checked: boolean) => void;
  /** Rótulo acessível (o botão não tem texto). */
  label: string;
}

/** Interruptor (role="switch") com área de toque 52×44. */
export function Switch({ checked, onChange, label, className, ...rest }: SwitchProps) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      className={cx(styles.switch, className)}
      onClick={() => {
        onChange(!checked);
      }}
      {...rest}
    >
      <span className={cx(styles.track, checked && styles.on)} aria-hidden="true">
        <span className={styles.thumb} />
      </span>
    </button>
  );
}
