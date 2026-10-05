import type { Job } from '../../api/types';
import { formatAgo, formatEta } from '../../lib/format';
import { displayName, mixPath } from '../../lib/session';
import { ordinal, strings } from '../../strings';
import { Button, ButtonLink } from '../../ui/Button';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import { useReprocessSession } from '../session/hooks';
import { useCancelJob, useDiscardJob } from './hooks';
import styles from './JobCard.module.css';
import { JobStages } from './JobStages';

interface JobCardProps {
  job: Job;
  /** Versão do dock do desktop (mais densa). */
  compact?: boolean;
  /** Dentro do sheet: links substituem a entrada do histórico que abriu o sheet. */
  replaceOnNavigate?: boolean;
  /** Na fila: quando a GPU deve chegar neste job (ETA do job da frente). */
  startsInS?: number | null;
}

function RunningCard({ job, compact }: JobCardProps) {
  const cancel = useCancelJob();
  const eta = formatEta(job.eta_s);
  return (
    <div className={cx(styles.card, styles.running, compact && styles.compact)}>
      <div className={styles.head}>
        <span className={styles.code}>{job.session.code}</span>
        <span className={styles.now}>{strings.processing.now}</span>
      </div>
      <div className={styles.name}>{displayName(job.session)}</div>
      <JobStages job={job} />
      <div className={styles.footer}>
        <span className={styles.eta}>{eta ? strings.processing.remaining(eta) : ''}</span>
        <Button
          variant="ghost"
          size="sm"
          disabled={cancel.isPending}
          onClick={() => {
            cancel.mutate(job.id);
          }}
        >
          {strings.processing.cancel}
        </Button>
      </div>
    </div>
  );
}

function QueuedCard({ job, compact, startsInS }: JobCardProps) {
  const cancel = useCancelJob();
  const eta = formatEta(startsInS);
  const name = displayName(job.session);
  return (
    <div className={cx(styles.card, styles.row, compact && styles.compact)}>
      <span className={styles.position}>{ordinal(job.position ?? 1)}</span>
      <div className={styles.text}>
        <div className={styles.name}>{name}</div>
        <div className={styles.meta}>
          {compact ? strings.processing.inQueue : strings.processing.queuedStarts(eta)}
        </div>
      </div>
      <Button
        variant="ghost"
        icon="close"
        iconOnly
        label={strings.processing.cancelQueued(name)}
        disabled={cancel.isPending}
        onClick={() => {
          cancel.mutate(job.id);
        }}
      />
    </div>
  );
}

function FailedCard({ job, compact }: JobCardProps) {
  const retry = useReprocessSession();
  const discard = useDiscardJob();
  const message =
    job.error_message ?? job.session.error_message ?? strings.processing.failedFallback;
  return (
    <div className={cx(styles.card, styles.failed, compact && styles.compact)}>
      <div className={styles.head}>
        <Icon name="error" size={18} className={styles.badIcon} />
        <span className={styles.name}>{displayName(job.session)}</span>
        <span className={styles.code}>{job.session.code}</span>
      </div>
      <div className={styles.error}>{message}</div>
      <div className={styles.actions}>
        <Button
          variant="secondary"
          size="sm"
          icon="refresh"
          disabled={retry.isPending}
          onClick={() => {
            retry.mutate(job.session_id);
          }}
        >
          {strings.common.retry}
        </Button>
        <Button
          variant="ghost"
          size="sm"
          disabled={discard.isPending}
          onClick={() => {
            discard.mutate(job.id);
          }}
        >
          {strings.processing.discard}
        </Button>
      </div>
    </div>
  );
}

function DoneCard({ job, compact, replaceOnNavigate }: JobCardProps) {
  const discard = useDiscardJob();
  return (
    <div className={cx(styles.card, styles.row, compact && styles.compact)}>
      <Icon name="check_circle" className={styles.goodIcon} />
      <div className={styles.text}>
        <div className={styles.name}>{displayName(job.session)}</div>
        <div className={styles.meta}>
          {strings.processing.readyAgo(formatAgo(job.finished_at ?? job.created_at))}
        </div>
      </div>
      <ButtonLink
        variant="primary"
        size="sm"
        to={mixPath(job.session_id)}
        replace={replaceOnNavigate}
        onClick={() => {
          discard.mutate(job.id);
        }}
      >
        {strings.processing.openMixer}
      </ButtonLink>
    </div>
  );
}

/** Um job no sheet (celular) ou no dock (desktop), com as ações do seu estado. */
export function JobCard(props: JobCardProps) {
  switch (props.job.state) {
    case 'running':
      return <RunningCard {...props} />;
    case 'queued':
      return <QueuedCard {...props} />;
    case 'failed':
      return <FailedCard {...props} />;
    case 'done':
      return <DoneCard {...props} />;
    case 'cancelled':
      return null;
  }
}
