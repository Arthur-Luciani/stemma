import type { QueryClient } from '@tanstack/react-query';

import type { Export, Job, LiveEvent, Session } from '../api/types';
import { queryKeys } from './queryKeys';

/** Jobs que o `GET /api/jobs` lista (ver contrato da F2a/F2b). */
function isListed(job: Job): boolean {
  if (job.dismissed_at !== null || job.state === 'cancelled') return false;
  if (job.kind === 'export') return job.state === 'queued' || job.state === 'running';
  return true;
}

function upsertJob(jobs: Job[], job: Job): Job[] {
  const rest = jobs.filter((j) => j.id !== job.id);
  return isListed(job) ? [...rest, job] : rest;
}

function patchEmbeddedSession(jobs: Job[], session: Session): Job[] {
  if (!jobs.some((job) => job.session_id === session.id)) return jobs;
  return jobs.map((job) => (job.session_id === session.id ? { ...job, session } : job));
}

/** Lista de exports da sessão, mais recentes primeiro (como o `GET` devolve). */
function upsertExport(exports: Export[], item: Export): Export[] {
  const rest = exports.filter((e) => e.id !== item.id);
  return [item, ...rest].sort((a, b) => b.created_at.localeCompare(a.created_at));
}

export interface LiveEventHandler {
  handle: (event: LiveEvent) => void;
  /** Depois de uma reconexão: refaz tudo, porque eventos podem ter se perdido. */
  resync: () => void;
  dispose: () => void;
}

/**
 * Aplica os eventos do `/ws` no cache do Query. Cada evento é o estado atual da entidade,
 * então sobrescreve o que houver. Listas de sessões (com filtro, busca e contagens) não dá
 * para recalcular no cliente: são invalidadas, com debounce para não refazer o GET a cada %.
 */
export function createLiveEventHandler(
  queryClient: QueryClient,
  { listDebounceMs = 400 }: { listDebounceMs?: number } = {},
): LiveEventHandler {
  let timer: ReturnType<typeof setTimeout> | null = null;

  const invalidateLists = () => {
    if (timer !== null) return;
    timer = setTimeout(() => {
      timer = null;
      void queryClient.invalidateQueries({ queryKey: queryKeys.sessionLists });
    }, listDebounceMs);
  };

  const setSession = (session: Session) => {
    queryClient.setQueryData(queryKeys.session(session.id), session);
    queryClient.setQueryData<Job[]>(queryKeys.jobs, (jobs) =>
      jobs ? patchEmbeddedSession(jobs, session) : jobs,
    );
  };

  const handle = (event: LiveEvent) => {
    switch (event.type) {
      case 'session.updated':
        setSession(event.data.session);
        invalidateLists();
        break;
      case 'session.deleted':
        queryClient.removeQueries({ queryKey: queryKeys.session(event.data.id), exact: true });
        queryClient.setQueryData<Job[]>(queryKeys.jobs, (jobs) =>
          jobs?.filter((job) => job.session_id !== event.data.id),
        );
        invalidateLists();
        break;
      case 'job.updated':
        queryClient.setQueryData<Job[]>(queryKeys.jobs, (jobs) =>
          jobs ? upsertJob(jobs, event.data.job) : jobs,
        );
        setSession(event.data.job.session);
        break;
      case 'export.updated': {
        const item = event.data.export;
        // Só atualiza a lista que já foi carregada; quem abrir depois faz o GET.
        queryClient.setQueryData<Export[]>(queryKeys.exports(item.session_id), (exports) =>
          exports ? upsertExport(exports, item) : exports,
        );
        break;
      }
    }
  };

  return {
    handle,
    resync: () => void queryClient.invalidateQueries(),
    dispose: () => {
      if (timer !== null) clearTimeout(timer);
      timer = null;
    },
  };
}
