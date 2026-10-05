import type { Session } from '../../api/types';
import { formatDuration, formatShortDate } from '../../lib/format';
import { strings } from '../../strings';
import { ButtonLink } from '../../ui/Button';
import { StatusChip } from '../../ui/StatusChip';
import styles from './SessionHeader.module.css';

/** Cabeçalho igual ao do mixer: título 26/600; artista · ST-### · duração · data. */
export function SessionHeader({
  session,
  position,
  showChip = true,
}: {
  session: Session;
  position?: number | null;
  showChip?: boolean;
}) {
  return (
    <div className={styles.header}>
      <ButtonLink
        to="/sessions"
        variant="ghost"
        size="sm"
        icon="arrow_back"
        className={styles.back}
      >
        {strings.session.back}
      </ButtonLink>
      <div className={styles.row}>
        <div className={styles.text}>
          <h1 className={styles.title}>{session.title}</h1>
          <div className={styles.meta}>
            {session.artist} ·{' '}
            <span className={styles.mono}>
              {[
                session.code,
                formatDuration(session.duration_s),
                formatShortDate(session.created_at),
              ].join(' · ')}
            </span>
          </div>
        </div>
        {showChip && (
          <StatusChip state={session.state} progress={session.progress} position={position} />
        )}
      </div>
    </div>
  );
}
