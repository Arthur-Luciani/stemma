import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';

import { resetViewport, installMatchMedia } from './media';
import { pwaFake } from './pwaRegister';
import { server } from './server';
import { FakeWebSocket } from './websocket';

installMatchMedia();

// O jsdom não implementa pointer capture (faders e linha do tempo usam).
const captured = new WeakMap<Element, Set<number>>();
Element.prototype.setPointerCapture = function (this: Element, id: number) {
  const set = captured.get(this) ?? new Set<number>();
  set.add(id);
  captured.set(this, set);
};
Element.prototype.releasePointerCapture = function (this: Element, id: number) {
  captured.get(this)?.delete(id);
};
Element.prototype.hasPointerCapture = function (this: Element, id: number) {
  return captured.get(this)?.has(id) ?? false;
};
// Como no navegador, soltar o ponteiro libera a captura.
for (const type of ['pointerup', 'pointercancel']) {
  document.addEventListener(
    type,
    (event) => {
      if (event.target instanceof Element)
        captured.get(event.target)?.delete((event as PointerEvent).pointerId);
    },
    true,
  );
}

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
  // O app abre o `/ws` no layout; nos testes o socket é o `FakeWebSocket`. Precisa vir depois
  // do `listen`, porque o MSW 2 também troca o WebSocket global.
  vi.stubGlobal('WebSocket', FakeWebSocket);
});

afterEach(() => {
  cleanup();
  server.resetHandlers();
  resetViewport();
  FakeWebSocket.instances.length = 0;
  window.localStorage.clear();
  pwaFake.reset();
});

afterAll(() => {
  server.close();
});
