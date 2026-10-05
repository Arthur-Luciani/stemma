import type { Job } from '../../api/types';
import { JobCard } from './JobCard';
import { startEstimates } from './hooks';
import styles from './ProcessingList.module.css';

interface ProcessingListProps {
  jobs: readonly Job[];
  compact?: boolean;
  replaceOnNavigate?: boolean;
}

export function ProcessingList({ jobs, compact, replaceOnNavigate }: ProcessingListProps) {
  const starts = startEstimates(jobs);
  return (
    <ul className={styles.list}>
      {jobs.map((job) => (
        <li key={job.id}>
          <JobCard
            job={job}
            compact={compact}
            replaceOnNavigate={replaceOnNavigate}
            startsInS={starts.get(job.id)}
          />
        </li>
      ))}
    </ul>
  );
}
