import { useUrlParam } from '../../app/useUrlParam';
import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { Spinner } from '../../ui/Spinner';
import { useSystemUpdate } from './hooks';
import { showsNotice, updateView } from './status';
import styles from './Update.module.css';

/** Parâmetro da URL que abre o sheet/dialog de atualização (o back do Android fecha). */
export const UPDATE_PARAM = 'atualizacao';

function useNotice() {
  const { data } = useSystemUpdate();
  const [, open] = useUrlParam(UPDATE_PARAM);
  const view = data ? updateView(data) : null;
  return {
    view: view && showsNotice(view) ? view : null,
    open: () => {
      open('1');
    },
  };
}

/** Desktop: chip discreto na topbar, ao lado do QR. */
export function UpdateChip() {
  const { view, open } = useNotice();
  if (!view) return null;
  const running = view.kind === 'running';
  return (
    <button type="button" className={styles.chip} aria-haspopup="dialog" onClick={open}>
      <span className={styles.chipInner}>
        {running ? <Spinner size={18} /> : <span className={styles.dot} aria-hidden="true" />}
        {running ? strings.update.updating : strings.update.available(view.target)}
      </span>
    </button>
  );
}

/** Celular: faixa fina no topo do Descobrir e da Biblioteca. */
export function UpdateBanner() {
  const { view, open } = useNotice();
  if (!view) return null;
  const running = view.kind === 'running';
  return (
    <div className={styles.banner} role="status">
      {running ? <Spinner size={18} /> : <span className={styles.dot} aria-hidden="true" />}
      <span className={styles.bannerText}>
        {running ? strings.update.updating : strings.update.availableLong(view.target)}
      </span>
      <Button variant="ghost" size="sm" onClick={open} aria-haspopup="dialog">
        {strings.update.view}
      </Button>
    </div>
  );
}
