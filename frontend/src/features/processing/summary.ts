import type { Job } from '../../api/types';
import { formatEta } from '../../lib/format';
import { strings } from '../../strings';

export interface ProcessingSummary {
  /** Job em destaque: o que roda, senão o 1º da fila, senão o encerrado mais recente. */
  job: Job;
  active: boolean;
  /** Ex.: `Separando`, `Na fila`, `Falhou`, `Pronta`. */
  stage: string;
  /** Ex.: `62% · ~40s`. */
  detail: string | null;
  progress: number;
  /** Outros jobs ativos além do destaque. */
  more: number;
}

export function summarize(sorted: readonly Job[]): ProcessingSummary | null {
  const job = sorted[0];
  if (!job) return null;
  const activeCount = sorted.filter((j) => j.state === 'running' || j.state === 'queued').length;
  const active = job.state === 'running' || job.state === 'queued';

  let stage: string;
  let detail: string | null = null;
  if (job.state === 'running') {
    stage = job.stage === 'separating' ? strings.states.separating : strings.states.downloading;
    const eta = formatEta(job.eta_s);
    detail = [`${String(Math.round(job.progress))}%`, eta].filter(Boolean).join(' · ');
  } else if (job.state === 'queued') {
    stage = strings.states.queued;
  } else if (job.state === 'failed') {
    stage = strings.states.failed;
  } else {
    stage = strings.states.ready;
  }

  return {
    job,
    active,
    stage,
    detail,
    progress: job.state === 'running' ? job.progress : job.state === 'done' ? 100 : 0,
    more: Math.max(0, activeCount - (active ? 1 : 0)),
  };
}
