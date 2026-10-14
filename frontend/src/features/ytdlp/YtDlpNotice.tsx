import updateStyles from '../update/Update.module.css';
import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { Spinner } from '../../ui/Spinner';
import { useStartYtDlpUpdate, useYtDlp } from './hooks';
import { ytdlpView } from './status';

/**
 * Aviso de yt-dlp atrasado (ADR 0016): só quando a atualização diária não instalou uma
 * versão que saiu há dias (`stale`), e enquanto ela roda. No resto do tempo não há nada fixo
 * no app sobre o yt-dlp.
 */
function useNotice() {
  const { data } = useYtDlp();
  const start = useStartYtDlpUpdate();
  const view = data ? ytdlpView(data) : null;
  const running = view?.kind === 'running';
  const show =
    data !== undefined &&
    data.can_update &&
    (running || (data.stale && view?.kind === 'available'));
  return {
    show,
    running,
    canStart: !running && data !== undefined && data.active_jobs === 0 && !start.isPending,
    start: () => {
      start.mutate();
    },
  };
}

/** Desktop: chip na topbar, ao lado do aviso de versão nova do Stemma. */
export function YtDlpChip() {
  const notice = useNotice();
  if (!notice.show) return null;
  return (
    <button
      type="button"
      className={updateStyles.chip}
      disabled={!notice.canStart}
      onClick={notice.start}
    >
      <span className={updateStyles.chipInner}>
        {notice.running ? (
          <Spinner size={18} />
        ) : (
          <span className={updateStyles.dot} aria-hidden="true" />
        )}
        {notice.running ? strings.ytdlp.updatingShort : strings.ytdlp.update}
      </span>
    </button>
  );
}

/** Celular: faixa fina no topo do Descobrir e da Biblioteca. */
export function YtDlpBanner() {
  const notice = useNotice();
  if (!notice.show) return null;
  return (
    <div className={updateStyles.banner} role="status">
      {notice.running ? (
        <Spinner size={18} />
      ) : (
        <span className={updateStyles.dot} aria-hidden="true" />
      )}
      <span className={updateStyles.bannerText}>
        {notice.running ? strings.ytdlp.updatingShort : strings.ytdlp.stale}
      </span>
      {!notice.running && (
        <Button variant="ghost" size="sm" disabled={!notice.canStart} onClick={notice.start}>
          {strings.update.confirm}
        </Button>
      )}
    </div>
  );
}
