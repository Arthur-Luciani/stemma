import { useParams } from 'react-router';

import { NotFound } from '../../app/RouteError';
import { strings } from '../../strings';
import { EmptyState } from '../../ui/EmptyState';
import { SkeletonList } from '../../ui/Skeleton';
import { useOpenedSession } from './hooks';
import { SessionHeader } from './SessionHeader';
import styles from './SessionPage.module.css';

/** `/sessions/:id/mix`: placeholder até a F4 (mixer e AudioEngine). */
export function MixPlaceholderPage() {
  const { id = '' } = useParams();
  const { session, notFound } = useOpenedSession(id);

  if (notFound) return <NotFound />;

  return (
    <div className={styles.page}>
      {session ? (
        <SessionHeader session={session} />
      ) : (
        <SkeletonList rows={1} thumb={false} label={strings.app.loading} />
      )}
      <EmptyState
        icon="tune"
        title={strings.session.mixerSoon}
        body={strings.session.mixerSoonBody}
      />
    </div>
  );
}
