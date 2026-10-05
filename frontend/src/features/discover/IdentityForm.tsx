import { useState, type FormEvent } from 'react';

import { isApiError } from '../../api/client';
import type { SearchResult } from '../../api/types';
import { errorMessage } from '../../app/useErrorToast';
import { formatDuration, formatEta } from '../../lib/format';
import { sessionPath } from '../../lib/session';
import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/Icon';
import { TextField } from '../../ui/TextField';
import { useToast } from '../../ui/toastContext';
import { queueForecast, useJobs } from '../processing/hooks';
import { ArtistField } from './ArtistField';
import { DraftKeptError, useSeparate } from './hooks';
import styles from './IdentityForm.module.css';
import { Thumbnail } from './Thumbnail';

interface IdentityFormProps {
  result: SearchResult;
  /** `card`: passo 2 do desktop. `sheet`: bottom sheet do celular (mostra o vídeo). */
  variant: 'card' | 'sheet';
  onSeparated: () => void;
}

export function QueueForecast() {
  const { data: jobs } = useJobs();
  const { ahead, startsInS } = queueForecast(jobs ?? []);
  return (
    <div className={styles.forecast}>
      <Icon name="schedule" size={18} />
      {ahead === 0
        ? strings.identity.startsNow
        : strings.identity.ahead(ahead, formatEta(startsInS))}
    </div>
  );
}

/** Confirma artista e título (pré-preenchidos do YouTube) e manda separar. */
export function IdentityForm({ result, variant, onSeparated }: IdentityFormProps) {
  const [artist, setArtist] = useState(result.artist);
  const [title, setTitle] = useState(result.title);
  const separate = useSeparate();
  const toast = useToast();
  const valid = artist.trim().length > 0 && title.trim().length > 0;

  const onSubmit = (event: FormEvent) => {
    event.preventDefault();
    if (!valid || separate.isPending) return;
    separate.mutate(
      { result, identity: { artist: artist.trim(), title: title.trim() } },
      {
        onSuccess: (job) => {
          toast.show({
            tone: 'good',
            message: strings.identity.queued(job.session.code),
            action: { label: strings.identity.follow, to: sessionPath(job.session_id) },
          });
          onSeparated();
        },
        onError: (error) => {
          if (error instanceof DraftKeptError) {
            const reason = isApiError(error.cause) ? ` ${error.cause.message}` : '';
            toast.show({
              tone: 'bad',
              message: `${strings.identity.keptAsDraft(error.session.code)}.${reason}`,
              action: { label: strings.identity.continue, to: sessionPath(error.session.id) },
            });
            onSeparated();
            return;
          }
          toast.show({ tone: 'bad', message: errorMessage(error) });
        },
      },
    );
  };

  return (
    <form className={styles[variant]} onSubmit={onSubmit} noValidate>
      {variant === 'sheet' ? (
        <div className={styles.video}>
          <Thumbnail result={result} size="sm" />
          <div className={styles.videoText}>
            <div className={styles.videoTitle}>{result.source_title}</div>
            <div className={styles.videoMeta}>
              {[formatDuration(result.duration_s), result.source_channel]
                .filter(Boolean)
                .join(' · ')}
            </div>
          </div>
        </div>
      ) : (
        <div className={styles.step}>{strings.identity.step}</div>
      )}
      <h2 className={styles.title}>{strings.identity.title}</h2>
      <ArtistField value={artist} onChange={setArtist} showUsedHint={variant === 'card'} />
      <TextField
        label={strings.identity.songTitle}
        value={title}
        autoComplete="off"
        onChange={(event) => {
          setTitle(event.target.value);
        }}
      />
      {variant === 'card' && <div className={styles.hint}>{strings.identity.prefilled}</div>}
      <QueueForecast />
      {!valid && <div className={styles.invalid}>{strings.identity.required}</div>}
      <Button
        type="submit"
        variant="primary"
        size="lg"
        icon="call_split"
        block
        disabled={!valid || separate.isPending}
      >
        {strings.identity.separate}
      </Button>
    </form>
  );
}
