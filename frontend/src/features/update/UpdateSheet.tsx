import type { SystemUpdate } from '../../api/types';
import { useUrlParam } from '../../app/useUrlParam';
import { strings } from '../../strings';
import { BottomSheet } from '../../ui/BottomSheet';
import { Button } from '../../ui/Button';
import { formatAgo } from '../../lib/format';
import { Dialog } from '../../ui/Dialog';
import { Icon } from '../../ui/Icon';
import { Spinner } from '../../ui/Spinner';
import { useIsDesktop } from '../../ui/useMediaQuery';
import { DiskUsage } from '../disk/DiskUsage';
import { useYtDlp } from '../ytdlp/hooks';
import { useCheckUpdate, useStartUpdate, useSystemUpdate } from './hooks';
import { type UpdateView, updateView } from './status';
import styles from './Update.module.css';
import { UPDATE_PARAM } from './UpdateNotice';

/**
 * Versão atual → nova, novidades e o botão Atualizar (`?atualizacao=1`). Dialog no desktop,
 * BottomSheet no celular. Acompanha a atualização até o fim (ou a falha).
 */
export function UpdateSheet() {
  const isDesktop = useIsDesktop();
  const [param, , close] = useUrlParam(UPDATE_PARAM);
  const { data } = useSystemUpdate();
  const start = useStartUpdate();
  const check = useCheckUpdate();
  const ytdlp = useYtDlp().data?.installed_version;
  const open = param === '1' && data !== undefined;
  if (!data) return null;

  const view = updateView(data);
  const canStart =
    view.kind === 'available' && data.can_update && data.active_jobs === 0 && !start.isPending;
  const offer = view.kind === 'available' && data.can_update;
  const body = (
    <>
      <UpdateBody data={data} view={view} />
      <CheckRow
        data={data}
        view={view}
        pending={check.isPending}
        onCheck={() => {
          check.mutate();
        }}
      />
      <DiskUsage enabled={open} />
      {ytdlp && <p className={styles.muted}>{strings.update.ytdlp(ytdlp)}</p>}
    </>
  );
  const actions = offer ? (
    <>
      <Button onClick={close}>{strings.update.later}</Button>
      <Button
        variant="primary"
        disabled={!canStart}
        onClick={() => {
          start.mutate();
        }}
      >
        {strings.update.confirm}
      </Button>
    </>
  ) : (
    <Button onClick={close}>{strings.common.close}</Button>
  );

  if (isDesktop) {
    return (
      <Dialog open={open} onClose={close} title={strings.update.title} actions={actions}>
        {body}
      </Dialog>
    );
  }
  return (
    <BottomSheet open={open} onClose={close} label={strings.update.title}>
      <div className={styles.sheet}>
        <h2 className={styles.sheetTitle}>{strings.update.title}</h2>
        {body}
        <div className={styles.sheetActions}>{actions}</div>
      </div>
    </BottomSheet>
  );
}

function UpdateBody({ data, view }: { data: SystemUpdate; view: UpdateView }) {
  switch (view.kind) {
    case 'running':
      return (
        <>
          <Versions from={data.current_version} to={view.target} />
          <p className={styles.progress} role="status">
            <Spinner size={18} />
            <span>{strings.update.updatingDetail(view.target)}</span>
          </p>
        </>
      );
    case 'updated':
      return (
        <div className={styles.good} role="status">
          <Icon name="check_circle" size={20} />
          <div>
            <p className={styles.strong}>{strings.update.updated(view.version)}</p>
            <p>{strings.update.updatedHint}</p>
          </div>
        </div>
      );
    case 'available':
      return (
        <>
          <Versions from={data.current_version} to={view.target} />
          {view.lastFailure && (
            <div className={styles.bad} role="alert">
              <Icon name="error" size={20} />
              <div>
                <p className={styles.strong}>{strings.update.failed}</p>
                <p>{view.lastFailure}</p>
              </div>
            </div>
          )}
          <Notes data={data} />
          {data.can_update ? (
            <>
              <p className={styles.muted}>{strings.update.downtime}</p>
              {data.active_jobs > 0 && (
                <p className={styles.warn}>{strings.update.jobsActive(data.active_jobs)}</p>
              )}
            </>
          ) : (
            <p className={styles.muted}>{strings.update.notSupported}</p>
          )}
        </>
      );
    case 'upToDate':
      return <p className={styles.muted}>{strings.update.upToDate(data.current_version)}</p>;
    case 'unknown':
      return <p className={styles.muted}>{strings.update.checkFailed}</p>;
  }
}

/** Versão instalada, "verificado há X" e o botão que consulta o GitHub agora. */
function CheckRow({
  data,
  view,
  pending,
  onCheck,
}: {
  data: SystemUpdate;
  view: UpdateView;
  pending: boolean;
  onCheck: () => void;
}) {
  const showVersion = view.kind !== 'running';
  const info = [
    showVersion ? strings.update.installed(data.current_version) : null,
    data.checked_at ? strings.update.checkedAgo(formatAgo(data.checked_at)) : null,
  ].filter((part) => part !== null);
  return (
    <div className={styles.checkRow}>
      {info.length > 0 && <p className={styles.muted}>{info.join(' · ')}</p>}
      <Button icon="refresh" disabled={pending || view.kind === 'running'} onClick={onCheck}>
        {pending ? strings.update.checking : strings.update.check}
      </Button>
    </div>
  );
}

function Versions({ from, to }: { from: string; to: string }) {
  return (
    <dl className={styles.versions}>
      <div>
        <dt>{strings.update.current}</dt>
        <dd>v{from}</dd>
      </div>
      <Icon name="arrow_forward" size={20} className={styles.arrow} />
      <div>
        <dt>{strings.update.next}</dt>
        <dd className={styles.target}>v{to}</dd>
      </div>
    </dl>
  );
}

function Notes({ data }: { data: SystemUpdate }) {
  const several = data.notes.length > 1;
  const empty = data.notes.every((release) => release.sections.length === 0);
  return (
    <section className={styles.notes} aria-label={strings.update.notes}>
      <h3 className={styles.notesTitle}>{strings.update.notes}</h3>
      {empty ? (
        <p className={styles.muted}>{strings.update.noNotes}</p>
      ) : (
        data.notes.map((release) => (
          <div key={release.version} className={styles.release}>
            {several && <h4 className={styles.releaseVersion}>v{release.version}</h4>}
            {release.sections.map((section, sectionIndex) => (
              // Títulos e itens podem se repetir (dois commits iguais): a posição entra na key.
              <div key={`${String(sectionIndex)}-${section.title}`}>
                <p className={styles.sectionTitle}>{section.title}</p>
                <ul className={styles.items}>
                  {section.items.map((item, itemIndex) => (
                    <li key={`${String(itemIndex)}-${item}`}>{item}</li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        ))
      )}
    </section>
  );
}
