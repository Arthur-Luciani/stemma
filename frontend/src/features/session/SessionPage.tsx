import { useState, type FormEvent } from 'react';
import { useParams } from 'react-router';

import type { Session } from '../../api/types';
import { NotFound } from '../../app/RouteError';
import { errorMessage } from '../../app/useErrorToast';
import { isActiveState, mixPath } from '../../lib/session';
import { strings } from '../../strings';
import { Button, ButtonLink } from '../../ui/Button';
import { ErrorState } from '../../ui/EmptyState';
import { SkeletonList } from '../../ui/Skeleton';
import { TextField } from '../../ui/TextField';
import { useToast } from '../../ui/toastContext';
import { ArtistField } from '../discover/ArtistField';
import { QueueForecast } from '../discover/IdentityForm';
import { useProcessingJobs } from '../processing/hooks';
import { ProcessingList } from '../processing/ProcessingList';
import { usePatchSession, useProcessSession, useOpenedSession, useReprocessSession } from './hooks';
import { SessionHeader } from './SessionHeader';
import styles from './SessionPage.module.css';

/** Rascunho: confere a identidade e manda separar ("Continuar" da biblioteca). */
function DraftPanel({ session }: { session: Session }) {
  const [artist, setArtist] = useState(session.artist);
  const [title, setTitle] = useState(session.title);
  const patch = usePatchSession();
  const process = useProcessSession();
  const toast = useToast();
  const valid = artist.trim().length > 0 && title.trim().length > 0;
  const busy = patch.isPending || process.isPending;

  const onSubmit = async (event: FormEvent) => {
    event.preventDefault();
    if (!valid || busy) return;
    const next = { artist: artist.trim(), title: title.trim() };
    try {
      if (next.artist !== session.artist || next.title !== session.title)
        await patch.mutateAsync({ id: session.id, patch: next });
    } catch (error) {
      toast.show({ tone: 'bad', message: errorMessage(error) });
      return;
    }
    process.mutate(session.id, {
      onSuccess: (job) => {
        toast.show({ tone: 'good', message: strings.identity.queued(job.session.code) });
      },
    });
  };

  return (
    <form className={styles.panel} onSubmit={(event) => void onSubmit(event)} noValidate>
      <p className={styles.hint}>{strings.session.draftHint}</p>
      <ArtistField value={artist} onChange={setArtist} showUsedHint />
      <TextField
        label={strings.identity.songTitle}
        value={title}
        autoComplete="off"
        onChange={(event) => {
          setTitle(event.target.value);
        }}
      />
      <QueueForecast />
      <Button
        type="submit"
        variant="primary"
        size="lg"
        icon="call_split"
        block
        disabled={!valid || busy}
      >
        {strings.identity.separate}
      </Button>
    </form>
  );
}

function ActivePanel({ session }: { session: Session }) {
  const jobs = useProcessingJobs().filter(
    (job) => job.session_id === session.id && (job.state === 'running' || job.state === 'queued'),
  );
  return <ProcessingList jobs={jobs} />;
}

function FailedPanel({ session }: { session: Session }) {
  const retry = useReprocessSession();
  return (
    <ErrorState
      icon="error"
      title={strings.states.failed}
      body={session.error_message ?? strings.processing.failedFallback}
      action={
        <Button
          variant="secondary"
          icon="refresh"
          disabled={retry.isPending}
          onClick={() => {
            retry.mutate(session.id);
          }}
        >
          {strings.common.retry}
        </Button>
      }
    />
  );
}

/** `/sessions/:id`: detalhe e acompanhamento (sem tela própria no design; ver Desvios). */
export function SessionPage() {
  const { id = '' } = useParams();
  const { query, session, notFound } = useOpenedSession(id);

  if (notFound) return <NotFound />;

  return (
    <div className={styles.page}>
      {query.isPending ? (
        <SkeletonList rows={2} thumb={false} label={strings.app.loading} />
      ) : query.isError ? (
        <ErrorState
          title={strings.errors.loadFailed}
          body={errorMessage(query.error)}
          action={
            <Button variant="secondary" onClick={() => void query.refetch()}>
              {strings.common.retry}
            </Button>
          }
        />
      ) : session ? (
        <>
          <SessionHeader session={session} />
          {session.state === 'draft' && <DraftPanel key={session.id} session={session} />}
          {isActiveState(session.state) && <ActivePanel session={session} />}
          {session.state === 'failed' && <FailedPanel session={session} />}
          {session.state === 'ready' && (
            <div className={styles.panel}>
              <p className={styles.hint}>{strings.session.readyHint}</p>
              <ButtonLink to={mixPath(session.id)} variant="primary" size="lg" icon="tune" block>
                {strings.session.openMixer}
              </ButtonLink>
            </div>
          )}
          <a className={styles.source} href={session.source_url} target="_blank" rel="noreferrer">
            {strings.session.source}
          </a>
        </>
      ) : null}
    </div>
  );
}
