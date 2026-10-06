import { formatDuration } from '../../lib/format';
import { cx } from '../../ui/cx';
import { rulerTicks } from './timeline';
import styles from './TimeRuler.module.css';

/** Régua de tempo acima das lanes (desktop). */
export function TimeRuler({ duration, className }: { duration: number; className?: string }) {
  return (
    <div className={cx(styles.ruler, className)} aria-hidden="true">
      {rulerTicks(duration).map((t) => (
        <span key={t} className={styles.tick} style={{ left: `${String((t / duration) * 100)}%` }}>
          {formatDuration(t)}
        </span>
      ))}
    </div>
  );
}
