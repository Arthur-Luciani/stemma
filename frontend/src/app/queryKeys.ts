import type { SessionListParams, Stem } from '../api/types';

/** Chaves do TanStack Query. Tudo de sessão começa com `['sessions']`. */
export const queryKeys = {
  sessions: ['sessions'] as const,
  sessionLists: ['sessions', 'list'] as const,
  sessionList: (params: SessionListParams) => ['sessions', 'list', params] as const,
  sessionLibrary: (params: Omit<SessionListParams, 'offset' | 'limit'>) =>
    ['sessions', 'list', 'library', params] as const,
  session: (id: string) => ['sessions', 'detail', id] as const,
  peaks: (id: string, stem: Stem) => ['sessions', 'peaks', id, stem] as const,
  mix: (id: string) => ['sessions', 'mix', id] as const,
  exports: (id: string) => ['sessions', 'exports', id] as const,
  jobs: ['jobs'] as const,
  systemUpdate: ['system', 'update'] as const,
  search: (q: string) => ['search', q] as const,
  artists: (q: string) => ['artists', q] as const,
};
