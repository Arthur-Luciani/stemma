import { QueryClient } from '@tanstack/react-query';

import { isApiError, NETWORK_ERROR } from '../api/client';

export function createQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        // O `/ws` mantém o cache em dia; o refetch é só a rede de segurança.
        staleTime: 30_000,
        // Erros da API são definitivos (404, 409, 422…); só a queda de rede merece nova tentativa.
        retry: (failureCount, error) => failureCount < 1 && isApiError(error, NETWORK_ERROR),
      },
      mutations: { retry: false },
    },
  });
}
