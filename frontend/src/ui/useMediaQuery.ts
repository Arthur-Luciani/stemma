import { useSyncExternalStore } from 'react';

/**
 * Desktop: 900px de largura **e** 600px de altura. O celular deitado (~950×420) fica no
 * layout de celular. Os `@media` dos CSS Modules repetem esta mesma query: mude junto.
 */
export const DESKTOP_QUERY = '(min-width: 900px) and (min-height: 600px)';

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

/** Desktop (topbar, tabela, card de identidade, dock); ver `DESKTOP_QUERY`. */
export function useIsDesktop(): boolean {
  return useMediaQuery(DESKTOP_QUERY);
}
