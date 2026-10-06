import { STANDALONE_QUERY } from '../lib/standaloneMode';
import { DESKTOP_QUERY } from '../ui/useMediaQuery';

let desktop = false;
let standalone = false;
const listeners = new Set<() => void>();

/** `matchMedia` falso: só entende as queries de desktop e de app instalado. Padrão: celular no navegador. */
export function installMatchMedia(): void {
  window.matchMedia = (query: string) =>
    ({
      matches: (query === DESKTOP_QUERY && desktop) || (query === STANDALONE_QUERY && standalone),
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

export function setStandalone(value: boolean): void {
  standalone = value;
}

export function resetViewport(): void {
  desktop = false;
  standalone = false;
}
