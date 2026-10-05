import type { SessionState } from '../api/types';
import { statusLabel } from '../lib/session';
import { cx } from './cx';
import { Icon } from './Icon';
import styles from './StatusChip.module.css';

interface StatusChipProps {
  state: SessionState;
  /** Progresso da etapa (0–100), para Baixando/Separando. */
  progress?: number;
  /** Posição na fila (a partir de 1), para Na fila. */
  position?: number | null;
  size?: 'md' | 'sm';
  className?: string;
}

const tone: Record<SessionState, string | undefined> = {
  draft: styles.neutral,
  queued: styles.neutral,
  downloading: styles.warn,
  separating: styles.warn,
  ready: styles.good,
  failed: styles.bad,
};

/** Chip de estado da sessão: 26px, raio 6, com ponto (ou ícone de erro). */
export function StatusChip({ state, progress, position, size = 'md', className }: StatusChipProps) {
  return (
    <span className={cx(styles.chip, tone[state], styles[size], className)}>
      {state === 'failed' ? (
        <Icon name="error" size={18} className={styles.icon} />
      ) : (
        <span className={cx(styles.dot, state === 'draft' && styles.hollow)} aria-hidden="true" />
      )}
      {statusLabel(state, progress, position)}
    </span>
  );
}
