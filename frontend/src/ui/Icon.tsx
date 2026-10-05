import { cx } from './cx';
import styles from './Icon.module.css';

interface IconProps {
  /** Nome do Material Symbols Rounded (ex.: `search`). */
  name: string;
  filled?: boolean;
  size?: 18 | 20 | 22 | 24 | 28;
  className?: string;
}

/** Ícone decorativo; o texto acessível fica no controle que o contém. */
export function Icon({ name, filled = false, size = 22, className }: IconProps) {
  return (
    <span
      aria-hidden="true"
      className={cx(styles.icon, filled && styles.filled, styles[`s${String(size)}`], className)}
    >
      {name}
    </span>
  );
}
