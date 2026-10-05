import { useState } from 'react';

import { displayName } from '../../lib/session';
import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/Icon';
import { ProgressBar } from '../../ui/ProgressBar';
import { Spinner } from '../../ui/Spinner';
import { useProcessingJobs } from './hooks';
import styles from './ProcessingDock.module.css';
import { ProcessingList } from './ProcessingList';
import { summarize, type ProcessingSummary } from './summary';

const STORAGE_KEY = 'stemma.dockExpanded';

function readExpanded(): boolean {
  try {
    return window.localStorage.getItem(STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

function writeExpanded(value: boolean): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, value ? '1' : '0');
  } catch {
    // Sem storage: só não lembra a preferência.
  }
}

export function SummaryIcon({ summary }: { summary: ProcessingSummary }) {
  if (summary.active) return <Spinner size={18} />;
  if (summary.job.state === 'failed') return <Icon name="error" size={20} className={styles.bad} />;
  return <Icon name="check_circle" size={20} className={styles.good} />;
}

/** Dock recolhível do desktop, no canto inferior direito. Some quando não há jobs. */
export function ProcessingDock() {
  const jobs = useProcessingJobs();
  const [expanded, setExpanded] = useState(readExpanded);
  const summary = summarize(jobs);
  if (!summary) return null;

  const toggle = () => {
    setExpanded((value) => {
      writeExpanded(!value);
      return !value;
    });
  };

  if (expanded) {
    return (
      <section className={styles.dockExpanded} aria-label={strings.processing.title}>
        <div className={styles.header}>
          <h2 className={styles.title}>{strings.processing.title}</h2>
          <Button
            variant="ghost"
            icon="expand_more"
            iconOnly
            label={strings.processing.collapse}
            className={styles.toggle}
            aria-expanded="true"
            onClick={toggle}
          />
        </div>
        <div className={styles.scroll}>
          <ProcessingList jobs={jobs} compact />
        </div>
      </section>
    );
  }

  const meta = [
    summary.stage,
    summary.detail,
    summary.more > 0 ? strings.processing.moreInQueue(summary.more) : null,
  ]
    .filter(Boolean)
    .join(' · ');

  return (
    <section className={styles.dock} aria-label={strings.processing.title}>
      <div className={styles.collapsed}>
        <SummaryIcon summary={summary} />
        <div className={styles.text}>
          <div className={styles.name}>{displayName(summary.job.session)}</div>
          <div className={styles.meta}>{meta}</div>
        </div>
        <Button
          variant="ghost"
          icon="expand_less"
          iconOnly
          label={strings.processing.expand}
          className={styles.toggle}
          aria-expanded="false"
          onClick={toggle}
        />
      </div>
      {summary.active && (
        <ProgressBar
          value={summary.progress}
          thin
          label={strings.processing.title}
          className={styles.bar}
        />
      )}
    </section>
  );
}
