import { DESKTOP_QUERY } from '../ui/useMediaQuery';

let desktop = false;
const listeners = new Set<() => void>();

/** `matchMedia` falso: só entende a query de desktop. Padrão: celular. */
export function installMatchMedia(): void {
  window.matchMedia = (query: string) =>
    ({
      matches: query === DESKTOP_QUERY && desktop,
      media: query,
      onchange: null,
      addEventListener: (_: string, listener: () => void) => listeners.add(listener),
      removeEventListener: (_: string, listener: () => void) => listeners.delete(listener),
      addListener: () => undefined,
      removeListener: () => undefined,
      dispatchEvent: () => false,
    }) as unknown as MediaQueryList;
}

export function setDesktop(value: boolean): void {
  desktop = value;
  listeners.forEach((listener) => {
    listener();
  });
}

export function resetViewport(): void {
  desktop = false;
}
