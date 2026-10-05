import { cx } from './cx';
import styles from './ProgressBar.module.css';

interface ProgressBarProps {
  /** 0–100. */
  value: number;
  tone?: 'warn' | 'good' | 'accent';
  label?: string;
  thin?: boolean;
  className?: string;
}

export function ProgressBar({ value, tone = 'warn', label, thin, className }: ProgressBarProps) {
  const pct = Math.max(0, Math.min(100, value));
  return (
    <div
      role="progressbar"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={Math.round(pct)}
      className={cx(styles.track, thin && styles.thin, className)}
    >
      {/* Largura dinâmica: único uso permitido de style inline. */}
      <div className={cx(styles.fill, styles[tone])} style={{ width: `${String(pct)}%` }} />
    </div>
  );
}
