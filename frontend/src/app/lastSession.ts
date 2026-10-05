import { useSyncExternalStore } from 'react';

/** Última sessão aberta: é para onde o "Mixer" da navegação aponta. */
const KEY = 'stemma.lastSession';
const listeners = new Set<() => void>();

function read(): string | null {
  try {
    return window.localStorage.getItem(KEY);
  } catch {
    return null;
  }
}

function write(id: string | null): void {
  try {
    if (id === null) window.localStorage.removeItem(KEY);
    else window.localStorage.setItem(KEY, id);
  } catch {
    // Sem storage (aba privada, bloqueio): a navegação só não lembra a sessão.
  }
  listeners.forEach((listener) => {
    listener();
  });
}

export function setLastSession(id: string): void {
  if (read() !== id) write(id);
}

export function clearLastSession(id?: string): void {
  if (id === undefined || read() === id) write(null);
}

export function useLastSession(): string | null {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    read,
    () => null,
  );
}
