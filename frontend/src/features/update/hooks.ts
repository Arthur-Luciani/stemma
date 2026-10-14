import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { checkSystemUpdate, getSystemUpdate, startSystemUpdate } from '../../api/endpoints';
import type { SystemUpdate } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { useErrorToast } from '../../app/useErrorToast';

/** Sem atualização em andamento: o backend consulta o GitHub com cache de horas. */
export const UPDATE_CHECK_MS = 60 * 60 * 1000;
/** Consulta barata (o backend tem cache): ao voltar para o app, confere de novo. */
export const UPDATE_STALE_MS = 5 * 60 * 1000;
/** Atualizando: acompanha até o servidor voltar e gravar o resultado. */
export const UPDATE_POLL_MS = 5000;

export function useSystemUpdate() {
  return useQuery({
    queryKey: queryKeys.systemUpdate,
    queryFn: ({ signal }) => getSystemUpdate(signal),
    staleTime: UPDATE_STALE_MS,
    // Durante a atualização o servidor sai do ar: os erros não apagam o último dado (que segue
    // "running") e a consulta continua a cada 5 s até ele voltar.
    refetchInterval: (query) =>
      query.state.data?.last_run?.state === 'running' ? UPDATE_POLL_MS : UPDATE_CHECK_MS,
    refetchIntervalInBackground: false,
    retry: false,
  });
}

/** "Verificar atualizações": o resultado vai direto para o cache, e o chip/faixa reagem. */
export function useCheckUpdate() {
  const client = useQueryClient();
  const onError = useErrorToast();
  return useMutation({
    mutationFn: checkSystemUpdate,
    onSuccess: async (data) => {
      // Um refetch em andamento não pode chegar depois e sobrescrever o resultado mais novo.
      await client.cancelQueries({ queryKey: queryKeys.systemUpdate });
      client.setQueryData<SystemUpdate>(queryKeys.systemUpdate, data);
    },
    onError,
  });
}

export function useStartUpdate() {
  const client = useQueryClient();
  const onError = useErrorToast();
  return useMutation({
    mutationFn: startSystemUpdate,
    onSuccess: (run) => {
      client.setQueryData<SystemUpdate>(queryKeys.systemUpdate, (old) =>
        old ? { ...old, last_run: run } : old,
      );
    },
    onError: (error) => {
      onError(error);
      void client.invalidateQueries({ queryKey: queryKeys.systemUpdate });
    },
  });
}
