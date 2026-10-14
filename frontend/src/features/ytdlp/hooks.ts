import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { getYtDlp, startYtDlpUpdate } from '../../api/endpoints';
import type { YtDlpStatus } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { useErrorToast } from '../../app/useErrorToast';
import { UPDATE_CHECK_MS, UPDATE_POLL_MS, UPDATE_STALE_MS } from '../update/hooks';

/**
 * Status do yt-dlp (ADR 0016), com o mesmo ritmo do status do Stemma (o backend tem cache).
 * Atualizando, acompanha a cada 5 s: o servidor sai do ar por uns 30 s e os erros não apagam
 * o último dado, que segue "running".
 */
export function useYtDlp() {
  return useQuery({
    queryKey: queryKeys.ytdlp,
    queryFn: ({ signal }) => getYtDlp(signal),
    staleTime: UPDATE_STALE_MS,
    refetchInterval: (query) =>
      query.state.data?.last_run?.state === 'running' ? UPDATE_POLL_MS : UPDATE_CHECK_MS,
    refetchIntervalInBackground: false,
    retry: false,
  });
}

export function useStartYtDlpUpdate() {
  const client = useQueryClient();
  const onError = useErrorToast();
  return useMutation({
    mutationFn: startYtDlpUpdate,
    onSuccess: (run) => {
      client.setQueryData<YtDlpStatus>(queryKeys.ytdlp, (old) =>
        old ? { ...old, last_run: run } : old,
      );
    },
    onError: (error) => {
      onError(error);
      void client.invalidateQueries({ queryKey: queryKeys.ytdlp });
    },
  });
}
