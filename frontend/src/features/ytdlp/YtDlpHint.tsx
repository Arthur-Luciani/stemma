import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/Icon';
import { Spinner } from '../../ui/Spinner';
import { useStartYtDlpUpdate, useYtDlp } from './hooks';
import { ytdlpView } from './status';
import styles from './YtDlp.module.css';

/**
 * Sugestão de atualizar o yt-dlp onde a falha aparece (card do job, erro da busca). Só
 * aparece com versão nova publicada, ou enquanto atualiza e logo depois. Atualizar não
 * reprocessa: o "Tentar de novo" de quem mostra o erro faz isso.
 */
export function YtDlpHint() {
  const { data } = useYtDlp();
  const start = useStartYtDlpUpdate();
  if (!data) return null;

  const view = ytdlpView(data);
  switch (view.kind) {
    case 'running':
      return (
        <p className={styles.progress} role="status">
          <Spinner size={18} />
          <span>{strings.ytdlp.updating(view.target)}</span>
        </p>
      );
    case 'updated':
      return (
        <p className={styles.good} role="status">
          <Icon name="check_circle" size={18} />
          <span>{strings.ytdlp.updated(view.version)}</span>
        </p>
      );
    case 'available': {
      if (!data.can_update) return null;
      const busy = data.active_jobs > 0;
      return (
        <div className={styles.hint}>
          <p className={styles.text}>{view.lastFailure ?? strings.ytdlp.newer(view.target)}</p>
          {busy && <p className={styles.warn}>{strings.ytdlp.jobsActive}</p>}
          <Button
            variant="secondary"
            size="sm"
            icon="update"
            disabled={busy || start.isPending}
            onClick={() => {
              start.mutate();
            }}
          >
            {strings.ytdlp.update}
          </Button>
        </div>
      );
    }
    case 'upToDate':
    case 'unknown':
      return null;
  }
}
