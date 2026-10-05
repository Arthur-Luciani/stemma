import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useMemo } from 'react';

import { cancelJob, discardJob, listJobs } from '../../api/endpoints';
import type { Job } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { useErrorToast } from '../../app/useErrorToast';

export function useJobs() {
  return useQuery({
    queryKey: queryKeys.jobs,
    queryFn: ({ signal }) => listJobs(signal),
  });
}

const order: Record<Job['state'], number> = {
  running: 0,
  queued: 1,
  failed: 2,
  done: 3,
  cancelled: 4,
};

/** Jobs de processamento do dock: rodando, fila por posição, depois encerrados (recentes antes). */
export function sortProcessingJobs(jobs: readonly Job[]): Job[] {
  return jobs
    .filter(
      (job) => job.kind === 'process' && job.dismissed_at === null && job.state !== 'cancelled',
    )
    .sort((a, b) => {
      const byState = order[a.state] - order[b.state];
      if (byState !== 0) return byState;
      if (a.state === 'queued') return (a.position ?? 0) - (b.position ?? 0);
      return (b.finished_at ?? b.created_at).localeCompare(a.finished_at ?? a.created_at);
    });
}

export function useProcessingJobs(): Job[] {
  const { data } = useJobs();
  return useMemo(() => sortProcessingJobs(data ?? []), [data]);
}

/**
 * Previsão para um job novo: quantos jobs de processamento estão na frente e quando a GPU
 * fica livre (o maior ETA entre eles).
 */
export function queueForecast(jobs: readonly Job[]): { ahead: number; startsInS: number | null } {
  const active = jobs.filter(
    (job) => job.kind === 'process' && (job.state === 'running' || job.state === 'queued'),
  );
  const etas = active.map((job) => job.eta_s).filter((eta): eta is number => eta !== null);
  return { ahead: active.length, startsInS: etas.length > 0 ? Math.max(...etas) : null };
}

/** Para cada job na fila: segundos até começar (o ETA do job logo à frente). */
export function startEstimates(sorted: readonly Job[]): Map<string, number | null> {
  const map = new Map<string, number | null>();
  let previous: Job | undefined;
  for (const job of sorted) {
    if (job.state === 'queued') map.set(job.id, previous ? previous.eta_s : null);
    if (job.state === 'running' || job.state === 'queued') previous = job;
  }
  return map;
}

export function useCancelJob() {
  const queryClient = useQueryClient();
  const onError = useErrorToast();
  return useMutation({
    mutationFn: cancelJob,
    onError,
    // O evento do `/ws` também chega, mas a fila muda de ordem.
    onSettled: () => queryClient.invalidateQueries({ queryKey: queryKeys.jobs }),
  });
}

export function useDiscardJob() {
  const queryClient = useQueryClient();
  const onError = useErrorToast();
  return useMutation({
    mutationFn: discardJob,
    // Some na hora; se falhar, o `onSettled` traz de volta.
    onMutate: (id: string) => {
      queryClient.setQueryData<Job[]>(queryKeys.jobs, (jobs) => jobs?.filter((j) => j.id !== id));
    },
    onError,
    onSettled: () => queryClient.invalidateQueries({ queryKey: queryKeys.jobs }),
  });
}
