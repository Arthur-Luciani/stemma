import { forwardRef, useId, type InputHTMLAttributes, type ReactNode } from 'react';

import { cx } from './cx';
import styles from './TextField.module.css';

interface TextFieldProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'size'> {
  label: string;
  /** Texto à direita dentro do campo (ex.: "já usado · 3 sessões"). */
  trailing?: ReactNode;
  hideLabel?: boolean;
}

export const TextField = forwardRef<HTMLInputElement, TextFieldProps>(function TextField(
  { label, trailing, hideLabel, className, id, ...rest },
  ref,
) {
  const autoId = useId();
  const inputId = id ?? autoId;
  return (
    <div className={cx(styles.field, className)}>
      <label htmlFor={inputId} className={cx(styles.label, hideLabel && styles.visuallyHidden)}>
        {label}
      </label>
      <div className={styles.box}>
        <input ref={ref} id={inputId} className={styles.input} {...rest} />
        {trailing && <span className={styles.trailing}>{trailing}</span>}
      </div>
    </div>
  );
});
