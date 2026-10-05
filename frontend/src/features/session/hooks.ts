import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';

import { isApiError } from '../../api/client';
import {
  deleteSession,
  getSession,
  patchSession,
  processSession,
  reprocessSession,
} from '../../api/endpoints';
import type { Job, Session, SessionPatch } from '../../api/types';
import { clearLastSession, setLastSession } from '../../app/lastSession';
import { queryKeys } from '../../app/queryKeys';
import { useErrorToast } from '../../app/useErrorToast';

export function useSession(id: string) {
  return useQuery({
    queryKey: queryKeys.session(id),
    queryFn: ({ signal }) => getSession(id, signal),
  });
}

/**
 * Sessão aberta numa tela (`/sessions/:id` e `/mix`): vira a "última sessão" do Mixer na
 * navegação; se não existir (404, ou id que não é UUID → 422), sai de lá.
 */
export function useOpenedSession(id: string) {
  const query = useSession(id);
  const session = query.data;
  const notFound =
    isApiError(query.error) && (query.error.status === 404 || query.error.status === 422);

  useEffect(() => {
    if (session) setLastSession(session.id);
  }, [session]);
  useEffect(() => {
    if (notFound) clearLastSession(id);
  }, [notFound, id]);

  return { query, session, notFound };
}

/** Depois de criar/enfileirar um job: a sessão e a fila mudaram. */
export function applyNewJob(queryClient: ReturnType<typeof useQueryClient>, job: Job): void {
  queryClient.setQueryData(queryKeys.session(job.session_id), job.session);
  queryClient.setQueryData<Job[]>(queryKeys.jobs, (jobs) =>
    jobs ? [...jobs.filter((j) => j.id !== job.id), job] : jobs,
  );
  void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
  void queryClient.invalidateQueries({ queryKey: queryKeys.sessionLists });
}

export function useProcessSession() {
  const queryClient = useQueryClient();
  const onError = useErrorToast();
  return useMutation({
    mutationFn: processSession,
    onSuccess: (job) => {
      applyNewJob(queryClient, job);
    },
    onError,
  });
}

/** "Tentar de novo" e "Reprocessar" são a mesma rota. */
export function useReprocessSession() {
  const queryClient = useQueryClient();
  const onError = useErrorToast();
  return useMutation({
    mutationFn: reprocessSession,
    onSuccess: (job) => {
      applyNewJob(queryClient, job);
    },
    onError,
  });
}

export function usePatchSession() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, patch }: { id: string; patch: SessionPatch }) => patchSession(id, patch),
    onSuccess: (session: Session) => {
      queryClient.setQueryData(queryKeys.session(session.id), session);
      void queryClient.invalidateQueries({ queryKey: queryKeys.sessionLists });
      void queryClient.invalidateQueries({ queryKey: ['artists'] });
    },
  });
}

export function useDeleteSession() {
  const queryClient = useQueryClient();
  const onError = useErrorToast();
  return useMutation({
    mutationFn: (session: Session) => deleteSession(session.id),
    onSuccess: (_, session) => {
      queryClient.removeQueries({ queryKey: queryKeys.session(session.id), exact: true });
      void queryClient.invalidateQueries({ queryKey: queryKeys.sessionLists });
      void queryClient.invalidateQueries({ queryKey: queryKeys.jobs });
    },
    onError,
  });
}
