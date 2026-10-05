import { Link } from 'react-router';

import type { Session } from '../../api/types';
import { formatDuration, formatShortDate } from '../../lib/format';
import { mixPath, sessionPath } from '../../lib/session';
import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { StatusChip } from '../../ui/StatusChip';
import type { SessionAct } from './actions';
import { PrimaryAction, SessionMenu } from './SessionActions';
import styles from './SessionItems.module.css';

interface ItemProps {
  session: Session;
  position?: number;
  open: (act: SessionAct, session: Session) => void;
}

const target = (s: Session) => (s.state === 'ready' ? mixPath(s.id) : sessionPath(s.id));

/** Linha da tabela do desktop: Código · Música · Estado · Duração · Criada · ações. */
export function SessionRow({ session, position, open }: ItemProps) {
  return (
    <tr className={styles.row}>
      <td className={styles.code}>{session.code}</td>
      <td className={styles.song}>
        <Link to={target(session)} className={styles.songLink}>
          <span className={styles.songTitle}>{session.title}</span>
          <span className={styles.songArtist}> · {session.artist}</span>
        </Link>
      </td>
      <td>
        <StatusChip
          state={session.state}
          progress={session.progress}
          position={position}
          size="sm"
        />
      </td>
      <td className={styles.mono}>{formatDuration(session.duration_s)}</td>
      <td className={styles.mono}>{formatShortDate(session.created_at)}</td>
      <td>
        <div className={styles.actions}>
          <PrimaryAction session={session} />
          <SessionMenu session={session} open={open} />
        </div>
      </td>
    </tr>
  );
}

/** Card do celular: título, artista · código · data, chip (se não pronta) e ⋯. */
export function SessionCard({ session, position, open }: ItemProps) {
  return (
    <li className={styles.card}>
      <Link to={target(session)} className={styles.cardLink}>
        <span className={styles.cardTitle}>{session.title}</span>
        <span className={styles.cardMeta}>
          {session.artist} ·{' '}
          <span className={styles.cardMono}>
            {session.code} · {formatShortDate(session.created_at)}
          </span>
        </span>
      </Link>
      {session.state !== 'ready' && (
        <StatusChip
          state={session.state}
          progress={session.progress}
          position={position}
          size="sm"
        />
      )}
      <Button
        variant="ghost"
        icon="more_vert"
        iconOnly
        label={`${strings.common.more}: ${session.title}`}
        aria-haspopup="dialog"
        onClick={() => {
          open('menu', session);
        }}
      />
    </li>
  );
}
