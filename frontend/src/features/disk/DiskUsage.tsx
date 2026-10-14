import { formatBytes } from '../../lib/format';
import { strings } from '../../strings';
import styles from './DiskUsage.module.css';
import { useDiskUsage } from './hooks';

/** Stems, exportações e backups do STORAGE_ROOT e o espaço livre do volume. */
export function DiskUsage({ enabled }: { enabled: boolean }) {
  const { data, isError } = useDiskUsage(enabled);
  if (isError) return <p className={styles.muted}>{strings.disk.unavailable}</p>;
  if (!data) return null;

  const rows: [string, string][] = [
    [strings.disk.stems, formatBytes(data.stems_bytes)],
    [strings.disk.exports, formatBytes(data.exports_bytes)],
    [strings.disk.backups, formatBytes(data.backups_bytes)],
    [
      strings.disk.free,
      strings.disk.freeOf(formatBytes(data.free_bytes), formatBytes(data.total_bytes)),
    ],
  ];
  return (
    <section className={styles.disk} aria-label={strings.disk.title}>
      <h3 className={styles.title}>{strings.disk.title}</h3>
      <dl className={styles.rows}>
        {rows.map(([label, value]) => (
          <div key={label} className={styles.row}>
            <dt>{label}</dt>
            <dd>{value}</dd>
          </div>
        ))}
      </dl>
      <p className={styles.muted}>{strings.disk.retention(data.exports_keep, data.backups_keep)}</p>
    </section>
  );
}
