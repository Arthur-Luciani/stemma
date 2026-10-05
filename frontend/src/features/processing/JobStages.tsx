import type { Job } from '../../api/types';
import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import { ProgressBar } from '../../ui/ProgressBar';
import styles from './JobStages.module.css';

type StepState = 'done' | 'current' | 'todo';

function Step({
  label,
  state,
  progress,
  wide,
}: {
  label: string;
  state: StepState;
  progress?: number;
  wide?: boolean;
}) {
  return (
    <div className={cx(styles.step, wide && styles.wide)}>
      <ProgressBar
        value={state === 'done' ? 100 : state === 'current' ? (progress ?? 0) : 0}
        tone={state === 'done' ? 'good' : 'warn'}
        label={label}
      />
      <div className={cx(styles.label, styles[state])}>{label}</div>
    </div>
  );
}

/** Baixado → Separando NN% → Pronto (a etapa atual é a mais larga). */
export function JobStages({ job }: { job: Job }) {
  const pct = Math.round(job.progress);
  const separating = job.stage === 'separating';
  const done = job.state === 'done';

  return (
    <div className={styles.stages}>
      <Step
        label={
          separating || done
            ? strings.processing.downloaded
            : `${strings.processing.downloading} ${String(pct)}%`
        }
        state={separating || done ? 'done' : 'current'}
        progress={pct}
        wide={!separating && !done}
      />
      <Step
        label={
          separating
            ? `${strings.processing.separating} ${String(pct)}%`
            : strings.processing.separating
        }
        state={done ? 'done' : separating ? 'current' : 'todo'}
        progress={pct}
        wide={separating}
      />
      <Step label={strings.processing.ready} state={done ? 'done' : 'todo'} />
    </div>
  );
}
