import { useState, type FormEvent } from 'react';

import type { Session } from '../../api/types';
import { errorMessage } from '../../app/useErrorToast';
import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { Dialog } from '../../ui/Dialog';
import { TextField } from '../../ui/TextField';
import { useToast } from '../../ui/toastContext';
import { ArtistField } from '../discover/ArtistField';
import { useDeleteSession, usePatchSession } from '../session/hooks';
import styles from './SessionDialogs.module.css';

interface DialogProps {
  session: Session;
  onClose: () => void;
}

const FORM_ID = 'edit-session-form';

export function EditSessionDialog({ session, onClose }: DialogProps) {
  const [artist, setArtist] = useState(session.artist);
  const [title, setTitle] = useState(session.title);
  const patch = usePatchSession();
  const toast = useToast();
  const valid = artist.trim().length > 0 && title.trim().length > 0;

  const onSubmit = (event: FormEvent) => {
    event.preventDefault();
    if (!valid || patch.isPending) return;
    patch.mutate(
      { id: session.id, patch: { artist: artist.trim(), title: title.trim() } },
      {
        onSuccess: () => {
          toast.show({ tone: 'good', message: strings.library.edited });
          onClose();
        },
      },
    );
  };

  return (
    <Dialog
      open
      onClose={onClose}
      title={strings.library.editTitle}
      actions={
        <>
          <Button variant="ghost" onClick={onClose}>
            {strings.common.cancel}
          </Button>
          <Button
            type="submit"
            form={FORM_ID}
            variant="primary"
            disabled={!valid || patch.isPending}
          >
            {strings.common.save}
          </Button>
        </>
      }
    >
      <form id={FORM_ID} className={styles.form} onSubmit={onSubmit} noValidate>
        <ArtistField value={artist} onChange={setArtist} />
        <TextField
          label={strings.identity.songTitle}
          value={title}
          autoComplete="off"
          onChange={(event) => {
            setTitle(event.target.value);
          }}
        />
        {patch.isError && (
          <p role="alert" className={styles.error}>
            {errorMessage(patch.error)}
          </p>
        )}
        {!valid && <p className={styles.error}>{strings.identity.required}</p>}
      </form>
    </Dialog>
  );
}

export function DeleteSessionDialog({ session, onClose }: DialogProps) {
  const remove = useDeleteSession();
  const toast = useToast();
  return (
    <Dialog
      open
      onClose={onClose}
      title={strings.library.deleteTitle(session.title)}
      actions={
        <>
          <Button variant="ghost" onClick={onClose} data-autofocus>
            {strings.common.cancel}
          </Button>
          <Button
            variant="destructive"
            disabled={remove.isPending}
            onClick={() => {
              remove.mutate(session, {
                onSuccess: () => {
                  toast.show({ tone: 'good', message: strings.library.deleted(session.code) });
                },
                // O erro (ex.: 409 session_busy) já vira toast no hook.
                onSettled: onClose,
              });
            }}
          >
            {strings.library.deleteConfirm}
          </Button>
        </>
      }
    >
      <p className={styles.body}>{strings.library.deleteBody(session.code)}</p>
    </Dialog>
  );
}
