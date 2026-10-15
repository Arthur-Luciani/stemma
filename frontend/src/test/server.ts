import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';

import {
  makeDefaultPresets,
  makeDiskUsage,
  makeSystemUpdate,
  makeYtDlpStatus,
  sessionList,
} from './fixtures';

/** Respostas padrão "vazias"; cada teste sobrescreve com `server.use(...)`. */
export const server = setupServer(
  http.get('*/api/jobs', () => HttpResponse.json({ items: [] })),
  http.get('*/api/sessions', () => HttpResponse.json(sessionList([]))),
  http.get('*/api/presets', () => HttpResponse.json({ items: makeDefaultPresets() })),
  http.get('*/api/artists', () => HttpResponse.json([])),
  http.get('*/api/system/update', () => HttpResponse.json(makeSystemUpdate())),
  http.get('*/api/system/disk', () => HttpResponse.json(makeDiskUsage())),
  http.get('*/api/system/ytdlp', () => HttpResponse.json(makeYtDlpStatus())),
);

export function apiError(status: number, code: string, message: string) {
  return HttpResponse.json({ error: { code, message } }, { status });
}
