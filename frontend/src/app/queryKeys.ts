import type { SessionListParams } from '../api/types';

/** Chaves do TanStack Query. Tudo de sessão começa com `['sessions']`. */
export const queryKeys = {
  sessions: ['sessions'] as const,
  sessionLists: ['sessions', 'list'] as const,
  sessionList: (params: SessionListParams) => ['sessions', 'list', params] as const,
  sessionLibrary: (params: Omit<SessionListParams, 'offset' | 'limit'>) =>
    ['sessions', 'list', 'library', params] as const,
  session: (id: string) => ['sessions', 'detail', id] as const,
  jobs: ['jobs'] as const,
  search: (q: string) => ['search', q] as const,
  artists: (q: string) => ['artists', q] as const,
};
