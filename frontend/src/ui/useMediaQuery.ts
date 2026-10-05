import { useSyncExternalStore } from 'react';

export const DESKTOP_QUERY = '(min-width: 900px)';

export function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const media = window.matchMedia(query);
      media.addEventListener('change', onChange);
      return () => {
        media.removeEventListener('change', onChange);
      };
    },
    () => window.matchMedia(query).matches,
    () => false,
  );
}

/** Desktop = 900px ou mais (topbar, tabela, card de identidade, dock). */
export function useIsDesktop(): boolean {
  return useMediaQuery(DESKTOP_QUERY);
}
