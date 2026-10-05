import { useUrlParam } from '../../app/useUrlParam';
import { strings } from '../../strings';
import { BottomSheet } from '../../ui/BottomSheet';
import { ProgressBar } from '../../ui/ProgressBar';
import { useProcessingJobs } from './hooks';
import { SummaryIcon } from './ProcessingDock';
import styles from './ProcessingPill.module.css';
import { ProcessingList } from './ProcessingList';
import { summarize } from './summary';

/** Pílula do celular, acima da bottom nav; abre o sheet de processamento (`?jobs=1`). */
export function ProcessingPill() {
  const jobs = useProcessingJobs();
  const [sheet, openSheet, closeSheet] = useUrlParam('jobs');
  const summary = summarize(jobs);
  const open = sheet === '1' && summary !== null;

  return (
    <>
      {summary && (
        <button
          type="button"
          className={styles.pill}
          aria-label={strings.processing.open}
          aria-haspopup="dialog"
          onClick={() => {
            openSheet('1');
          }}
        >
          <SummaryIcon summary={summary} />
          <span className={styles.name}>
            {summary.stage} · {summary.job.session.title}
          </span>
          {summary.detail && <span className={styles.detail}>{summary.detail}</span>}
          {summary.more > 0 && <span className={styles.more}>+{summary.more}</span>}
          {summary.active && <ProgressBar value={summary.progress} thin className={styles.bar} />}
        </button>
      )}
      <BottomSheet open={open} onClose={closeSheet} label={strings.processing.title} tall>
        <div className={styles.sheetHeader}>
          <h2 className={styles.sheetTitle}>{strings.processing.title}</h2>
          <span className={styles.gpu}>{strings.processing.gpu}</span>
        </div>
        <ProcessingList jobs={jobs} replaceOnNavigate />
      </BottomSheet>
    </>
  );
}
