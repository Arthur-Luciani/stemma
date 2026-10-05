import { keepPreviousData, useInfiniteQuery } from '@tanstack/react-query';

import { listSessions } from '../../api/endpoints';
import type { SessionCounts, SessionSort, SessionState } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { ACTIVE_STATES } from '../../lib/session';

export const PAGE_SIZE = 30;

export const FILTERS = ['all', 'ready', 'active', 'draft', 'failed'] as const;
export type LibraryFilter = (typeof FILTERS)[number];

export const SORTS = [
  'newest',
  'oldest',
  'title',
  'artist',
  'longest',
  'shortest',
] as const satisfies readonly SessionSort[];

export const filterStates: Record<LibraryFilter, SessionState[] | undefined> = {
  all: undefined,
  ready: ['ready'],
  active: [...ACTIVE_STATES],
  draft: ['draft'],
  failed: ['failed'],
};

export function filterCount(filter: LibraryFilter, counts: SessionCounts | undefined): number {
  if (!counts) return 0;
  const states = filterStates[filter] ?? (Object.keys(counts) as SessionState[]);
  return states.reduce((sum, state) => sum + counts[state], 0);
}

export function parseFilter(value: string | null): LibraryFilter {
  return (FILTERS as readonly string[]).includes(value ?? '') ? (value as LibraryFilter) : 'all';
}

export function parseSort(value: string | null): SessionSort {
  return (SORTS as readonly string[]).includes(value ?? '') ? (value as SessionSort) : 'newest';
}

export function useLibrary({
  q,
  filter,
  sort,
}: {
  q: string;
  filter: LibraryFilter;
  sort: SessionSort;
}) {
  const params = { q: q || undefined, state: filterStates[filter], sort };
  return useInfiniteQuery({
    queryKey: queryKeys.sessionLibrary(params),
    queryFn: ({ pageParam, signal }) =>
      listSessions({ ...params, limit: PAGE_SIZE, offset: pageParam }, signal),
    initialPageParam: 0,
    getNextPageParam: (last, pages) => {
      const loaded = pages.reduce((sum, page) => sum + page.items.length, 0);
      return loaded < last.total ? loaded : undefined;
    },
    // Trocar filtro/busca mantém a lista anterior na tela até chegar a nova.
    placeholderData: keepPreviousData,
  });
}
