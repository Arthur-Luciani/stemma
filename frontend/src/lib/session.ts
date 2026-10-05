import type { Job, SessionState } from '../api/types';
import { strings } from '../strings';

/** Estados com job ativo (o chip "Em andamento" da biblioteca soma os três). */
export const ACTIVE_STATES = [
  'queued',
  'downloading',
  'separating',
] as const satisfies readonly SessionState[];

export function isActiveState(state: SessionState): boolean {
  return (ACTIVE_STATES as readonly SessionState[]).includes(state);
}

export function statusLabel(state: SessionState, progress = 0, position?: number | null): string {
  if (state === 'queued' && position) return strings.chip.queuedAt(position);
  if (state === 'downloading' || state === 'separating')
    return strings.chip.progress(strings.states[state], progress);
  return strings.states[state];
}

/** `Artista — Título`, como no dock e no sheet de processamento. */
export function displayName(session: { artist: string; title: string }): string {
  return session.artist ? `${session.artist} — ${session.title}` : session.title;
}

export const sessionPath = (id: string) => `/sessions/${id}`;
export const mixPath = (id: string) => `/sessions/${id}/mix`;

/** Posição na fila por sessão, a partir dos jobs de processamento ativos. */
export function queuePositions(jobs: readonly Job[] | undefined): Map<string, number> {
  const map = new Map<string, number>();
  for (const job of jobs ?? []) {
    if (job.kind === 'process' && job.state === 'queued' && job.position !== null)
      map.set(job.session_id, job.position);
  }
  return map;
}
