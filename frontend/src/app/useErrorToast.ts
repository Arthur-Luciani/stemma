import { useCallback } from 'react';

import { isApiError } from '../api/client';
import { strings } from '../strings';
import { useToast } from '../ui/toastContext';

/** Mensagem para o usuário: a do backend (já em PT-BR) ou uma genérica. */
export function errorMessage(error: unknown): string {
  return isApiError(error) ? error.message : strings.errors.loadFailed;
}

/** `onError` padrão das mutations: toast com a mensagem do erro. */
export function useErrorToast(): (error: unknown) => void {
  const toast = useToast();
  return useCallback(
    (error: unknown) => {
      toast.show({ tone: 'bad', message: errorMessage(error) });
    },
    [toast],
  );
}
