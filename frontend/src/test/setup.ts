import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';

import { resetViewport, installMatchMedia } from './media';
import { server } from './server';
import { FakeWebSocket } from './websocket';

installMatchMedia();

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
});

afterAll(() => {
  server.close();
});
