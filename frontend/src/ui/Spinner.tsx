import { cx } from './cx';
import styles from './Spinner.module.css';

/** Anel girando em warn (processamento ativo). Decorativo: o texto ao lado diz o estado. */
export function Spinner({ size = 20, className }: { size?: 18 | 20; className?: string }) {
  return (
    <span
      aria-hidden="true"
      className={cx(styles.spinner, size === 18 && styles.small, className)}
    />
  );
}
