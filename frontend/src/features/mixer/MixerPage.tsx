import { useCallback } from 'react';
import { useParams } from 'react-router';

import type { Session } from '../../api/types';
import { NotFound } from '../../app/RouteError';
import { useUrlParam } from '../../app/useUrlParam';
import { strings } from '../../strings';
import { ButtonLink } from '../../ui/Button';
import { EmptyState, ErrorState } from '../../ui/EmptyState';
import { SkeletonList } from '../../ui/Skeleton';
import { useIsDesktop, useMediaQuery } from '../../ui/useMediaQuery';
import { EditSessionDialog } from '../library/SessionDialogs';
import { useOpenedSession } from '../session/hooks';
import { ConsoleMixer } from './ConsoleMixer';
import { DesktopMixer } from './DesktopMixer';
import { ExportSheet } from './ExportPanel';
import { useAudioEngine, usePeaks } from './hooks';
import { LanesMixer } from './LanesMixer';
import styles from './MixerPage.module.css';
import { PracticeMixer } from './PracticeMixer';
import { skip, useMixerShortcuts, type ShortcutAction } from './shortcuts';
import { useMixer } from './useMixer';
import type { MixerViewProps } from './views';

export const LANDSCAPE_QUERY = '(orientation: landscape) and (max-height: 600px)';

/** `/sessions/:id/mix`. */
export function MixerPage() {
  const { id = '' } = useParams();
  const { session, notFound, query } = useOpenedSession(id);

  if (notFound) return <NotFound />;
  if (!session) {
    return (
      <div className={styles.page}>
        {query.isError ? (
          <ErrorState title={strings.errors.loadFailed} />
        ) : (
          <SkeletonList rows={4} thumb={false} label={strings.app.loading} />
        )}
      </div>
    );
  }
  if (session.state !== 'ready') {
    return (
      <div className={styles.page}>
        <EmptyState
          icon="hourglass_empty"
          title={strings.mixer.notReady}
          body={strings.mixer.notReadyBody}
          action={
            <ButtonLink to={`/sessions/${session.id}`} variant="primary">
              {strings.mixer.openSession}
            </ButtonLink>
          }
        />
      </div>
    );
  }
  // Uma tela por sessão: trocar de sessão recria engine e mix do zero.
  return <MixerScreen key={session.id} session={session} />;
}

function MixerScreen({ session }: { session: Session }) {
  const isDesktop = useIsDesktop();
  const landscape = useMediaQuery(LANDSCAPE_QUERY);
  const [view, setView, clearView] = useUrlParam('view');
  const [exportParam, openExport, closeExport] = useUrlParam('export');
  const [edit, openEdit, closeEdit] = useUrlParam('edit');

  const { engine, error } = useAudioEngine(session.id);
  const peaks = usePeaks(session.id);
  const mixer = useMixer(session.id, engine);
  const { state, dispatch, markA, markB } = mixer;

  const onShortcut = useCallback(
    (action: ShortcutAction) => {
      switch (action.type) {
        case 'toggle':
          engine?.toggle();
          break;
        case 'skip':
          if (engine) skip(engine, action.delta);
          break;
        case 'mute':
        case 'solo':
          dispatch({ type: action.type, stem: action.stem });
          break;
        case 'markA':
          if (engine) markA(engine.getPosition());
          break;
        case 'markB':
          if (engine) markB(engine.getPosition());
          break;
      }
    },
    [engine, dispatch, markA, markB],
  );
  useMixerShortcuts(isDesktop && state !== null, onShortcut);

  if (error) {
    return (
      <div className={styles.page}>
        <ErrorState title={strings.mixer.loadFailed} body={error} />
      </div>
    );
  }
  if (!state) {
    return (
      <div className={styles.page}>
        {mixer.loadError ? (
          <ErrorState title={strings.errors.loadFailed} />
        ) : (
          <SkeletonList rows={4} thumb={false} label={strings.mixer.loading} />
        )}
      </div>
    );
  }

  const props: MixerViewProps = {
    session,
    engine,
    peaks,
    mixer: { ...mixer, state },
    duration: engine?.duration || session.duration_s || 0,
    exportOpen: exportParam !== null,
    onOpenExport: () => {
      openExport('1');
    },
    onCloseExport: closeExport,
    onEdit: () => {
      openEdit('1');
    },
  };

  return (
    <>
      {isDesktop ? (
        <DesktopMixer {...props} />
      ) : landscape ? (
        <ConsoleMixer {...props} />
      ) : view === 'ajustar' ? (
        <LanesMixer {...props} onBack={clearView} />
      ) : (
        <PracticeMixer
          {...props}
          onAdjust={() => {
            setView('ajustar');
          }}
        />
      )}
      {!isDesktop && (
        <ExportSheet
          session={session}
          mixer={props.mixer}
          open={props.exportOpen}
          onClose={closeExport}
        />
      )}
      {edit !== null && <EditSessionDialog session={session} onClose={closeEdit} />}
    </>
  );
}
