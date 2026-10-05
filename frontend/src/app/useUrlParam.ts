import { useCallback } from 'react';
import { useLocation, useNavigate, useSearchParams } from 'react-router';

interface UrlParamState {
  /** Quem abriu empilhou uma entrada no histórico; fechar volta (back do Android). */
  urlParam?: string;
}

/**
 * Um parâmetro da query string que controla algo aberto/fechado (sheet, seleção).
 * Abrir empilha no histórico, então o back do Android fecha em vez de sair da tela.
 */
export function useUrlParam(key: string) {
  const [params] = useSearchParams();
  const location = useLocation();
  const navigate = useNavigate();
  const value = params.get(key);

  const set = useCallback(
    (next: string, { replace = false }: { replace?: boolean } = {}) => {
      const search = new URLSearchParams(location.search);
      search.set(key, next);
      const alreadyOpen = new URLSearchParams(location.search).has(key);
      // Só marca quem empilhou: com `replace` (ou trocando o valor de algo já aberto) não há
      // entrada nova, e fechar não pode voltar no histórico.
      const push = !replace && !alreadyOpen;
      const state: unknown = push ? ({ urlParam: key } satisfies UrlParamState) : location.state;
      void navigate({ search: search.toString() }, { replace: !push, state });
    },
    [key, location.search, location.state, navigate],
  );

  const clear = useCallback(() => {
    const search = new URLSearchParams(location.search);
    if (!search.has(key)) return;
    if ((location.state as UrlParamState | null)?.urlParam === key) {
      void navigate(-1);
      return;
    }
    search.delete(key);
    void navigate({ search: search.toString() }, { replace: true });
  }, [key, location.search, location.state, navigate]);

  return [value, set, clear] as const;
}
