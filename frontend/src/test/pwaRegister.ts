/**
 * Substituto do `virtual:pwa-register/react` nos testes (alias no vite.config.ts).
 * `pwaFake.needRefresh(true)` simula uma versão nova esperando.
 */
import { useSyncExternalStore } from 'react';
import type { RegisterSWOptions } from 'vite-plugin-pwa/types';

let needRefreshValue = false;
let lastOptions: RegisterSWOptions | undefined;
const listeners = new Set<() => void>();

export const pwaFake = {
  updateServiceWorker: vi.fn<(reload?: boolean) => Promise<void>>(() => Promise.resolve()),
  /** Opções passadas ao último `useRegisterSW`. */
  options: () => lastOptions,
  needRefresh(value: boolean) {
    needRefreshValue = value;
    listeners.forEach((listener) => {
      listener();
    });
  },
  reset() {
    needRefreshValue = false;
    lastOptions = undefined;
    this.updateServiceWorker.mockClear();
  },
};

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function record(options: RegisterSWOptions | undefined) {
  lastOptions = options;
}

export function useRegisterSW(options?: RegisterSWOptions) {
  record(options);
  const needRefresh = useSyncExternalStore(subscribe, () => needRefreshValue);
  return {
    needRefresh: [
      needRefresh,
      (value: boolean) => {
        pwaFake.needRefresh(value);
      },
    ] as const,
    offlineReady: [false, () => undefined] as const,
    updateServiceWorker: pwaFake.updateServiceWorker,
  };
}
