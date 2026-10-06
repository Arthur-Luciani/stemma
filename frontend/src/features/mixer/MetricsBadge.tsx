import type { Session } from '../../api/types';
import { formatDb } from '../../lib/format';
import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import styles from './MetricsBadge.module.css';

/** LUFS integrado e true peak do áudio original; acima de 0 dBTP fica em vermelho. */
export function MetricsBadge({
  metrics,
  className,
}: {
  metrics: Session['metrics'];
  className?: string;
}) {
  const lufs = metrics?.lufs ?? null;
  const peak = metrics?.true_peak_db ?? null;
  return (
    <span className={cx(styles.metrics, className)} title={strings.mixer.metricsHint}>
      <span>
        <span className={styles.value}>{lufs === null ? '—' : formatDb(lufs)}</span>{' '}
        {strings.mixer.lufs}
      </span>
      <span>
        <span className={cx(styles.value, peak !== null && peak > 0 && styles.clip)}>
          {peak === null ? '—' : formatDb(peak, true)}
        </span>{' '}
        {strings.mixer.dbtp}
      </span>
    </span>
  );
}
