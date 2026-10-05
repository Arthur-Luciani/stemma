import { cx } from './cx';
import styles from './Skeleton.module.css';

/** Linhas de carregamento no formato de uma lista com miniatura (estado "Buscando"). */
export function SkeletonList({
  rows = 3,
  thumb = true,
  label,
}: {
  rows?: number;
  thumb?: boolean;
  label: string;
}) {
  return (
    <div className={styles.list} role="status" aria-label={label} aria-busy="true">
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className={cx(styles.row, i === rows - 1 && rows > 2 && styles.fade)}>
          {thumb && <div className={cx(styles.block, styles.thumb)} />}
          <div className={styles.lines}>
            <div className={cx(styles.block, styles.line, styles.wide)} />
            <div className={cx(styles.block, styles.line, styles.narrow)} />
          </div>
        </div>
      ))}
    </div>
  );
}
