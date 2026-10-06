import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';

import { makeSystemUpdate, sessionList } from './fixtures';

/** Respostas padrão "vazias"; cada teste sobrescreve com `server.use(...)`. */
export const server = setupServer(
  http.get('*/api/jobs', () => HttpResponse.json({ items: [] })),
  http.get('*/api/sessions', () => HttpResponse.json(sessionList([]))),
  http.get('*/api/artists', () => HttpResponse.json([])),
  http.get('*/api/system/update', () => HttpResponse.json(makeSystemUpdate())),
);

export function apiError(status: number, code: string, message: string) {
  return HttpResponse.json({ error: { code, message } }, { status });
}
