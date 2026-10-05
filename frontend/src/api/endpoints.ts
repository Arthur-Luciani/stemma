import { apiClient, call } from './client';
import type {
  Artist,
  Job,
  SearchResult,
  Session,
  SessionCreate,
  SessionList,
  SessionListParams,
  SessionPatch,
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
