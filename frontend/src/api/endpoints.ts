import { apiClient, call, toApiError } from './client';
import type {
  Artist,
  Export,
  ExportFormat,
  Job,
  MixState,
  MixStateIn,
  SearchResult,
  Session,
  SessionCreate,
  SessionList,
  SessionListParams,
  SessionPatch,
  Stem,
  StemPeaks,
  SystemUpdate,
  UpdateRun,
} from './types';

const path = (id: string) => ({ params: { path: { session_id: id } } });
const jobPath = (id: string) => ({ params: { path: { job_id: id } } });

export async function listSessions(
  params: SessionListParams = {},
  signal?: AbortSignal,
): Promise<SessionList> {
  const data = await call(() =>
    apiClient.GET('/api/sessions', { params: { query: params }, signal }),
  );
  return data as SessionList;
}

export function getSession(id: string, signal?: AbortSignal): Promise<Session> {
  return call(() => apiClient.GET('/api/sessions/{session_id}', { ...path(id), signal }));
}

export function createSession(body: SessionCreate): Promise<Session> {
  return call(() => apiClient.POST('/api/sessions', { body }));
}

export function patchSession(id: string, body: SessionPatch): Promise<Session> {
  return call(() => apiClient.PATCH('/api/sessions/{session_id}', { ...path(id), body }));
}

export async function deleteSession(id: string): Promise<void> {
  await call(() => apiClient.DELETE('/api/sessions/{session_id}', path(id)));
}

export function processSession(id: string): Promise<Job> {
  return call(() => apiClient.POST('/api/sessions/{session_id}/process', path(id)));
}

export function reprocessSession(id: string): Promise<Job> {
  return call(() => apiClient.POST('/api/sessions/{session_id}/reprocess', path(id)));
}

export async function listJobs(signal?: AbortSignal): Promise<Job[]> {
  const data = await call(() => apiClient.GET('/api/jobs', { signal }));
  return data.items;
}

export async function cancelJob(id: string): Promise<void> {
  await call(() => apiClient.DELETE('/api/jobs/{job_id}', jobPath(id)));
}

export async function discardJob(id: string): Promise<void> {
  await call(() => apiClient.POST('/api/jobs/{job_id}/discard', jobPath(id)));
}

export async function search(q: string, signal?: AbortSignal): Promise<SearchResult[]> {
  const data = await call(() => apiClient.GET('/api/search', { params: { query: { q } }, signal }));
  return data.items;
}

export function searchArtists(q: string, signal?: AbortSignal): Promise<Artist[]> {
  return call(() => apiClient.GET('/api/artists', { params: { query: { q, limit: 6 } }, signal }));
}

/** URL do MP3 do stem, para o `<audio>` do AudioEngine (o navegador faz os Range requests). */
export function stemUrl(id: string, stem: Stem): string {
  return `/api/sessions/${encodeURIComponent(id)}/stems/${stem}.mp3`;
}

function isStemPeaks(body: unknown): body is StemPeaks {
  if (typeof body !== 'object' || body === null) return false;
  const { duration_s, peaks } = body as Partial<StemPeaks>;
  return typeof duration_s === 'number' && Array.isArray(peaks);
}

export async function getPeaks(id: string, stem: Stem, signal?: AbortSignal): Promise<StemPeaks> {
  const data: unknown = await call(() =>
    apiClient.GET('/api/sessions/{session_id}/peaks/{stem}.json', {
      params: { path: { session_id: id, stem } },
      signal,
    }),
  );
  if (!isStemPeaks(data)) throw toApiError(200, data);
  return data;
}

export function getMix(id: string, signal?: AbortSignal): Promise<MixState> {
  return call(() => apiClient.GET('/api/sessions/{session_id}/mix', { ...path(id), signal }));
}

/** `keepalive`: o save do `pagehide` termina mesmo com a página indo embora. */
export function saveMix(
  id: string,
  body: MixStateIn,
  { keepalive = false }: { keepalive?: boolean } = {},
): Promise<MixState> {
  return call(() =>
    apiClient.PUT('/api/sessions/{session_id}/mix', { ...path(id), body, keepalive }),
  );
}

export async function listExports(id: string, signal?: AbortSignal): Promise<Export[]> {
  const data = await call(() =>
    apiClient.GET('/api/sessions/{session_id}/exports', { ...path(id), signal }),
  );
  return data.items;
}

/** Sem `stems`, o backend usa o mix salvo: salve antes de pedir. */
export function createExport(id: string, format: ExportFormat): Promise<Export> {
  return call(() =>
    apiClient.POST('/api/sessions/{session_id}/exports', { ...path(id), body: { format } }),
  );
}

/** URL do arquivo exportado (o backend manda `Content-Disposition` com o nome). */
export function exportFileUrl(exportId: string): string {
  return `/api/exports/${encodeURIComponent(exportId)}/file`;
}

/** Versão atual, última release e a última atualização pedida pelo app (ADR 0015). */
export function getSystemUpdate(signal?: AbortSignal): Promise<SystemUpdate> {
  return call(() => apiClient.GET('/api/system/update', { signal }));
}

/** Dispara a atualização (responde na hora; o servidor sai do ar por ~1 min). */
export function startSystemUpdate(): Promise<UpdateRun> {
  return call(() => apiClient.POST('/api/system/update'));
}
