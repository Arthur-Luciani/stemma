import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState } from 'react';

import {
  createSession,
  listSessions,
  processSession,
  search,
  searchArtists,
} from '../../api/endpoints';
import type { Job, SearchResult, Session } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { applyNewJob } from '../session/hooks';

export function useSearch(q: string) {
  return useQuery({
    queryKey: queryKeys.search(q),
    queryFn: ({ signal }) => search(q, signal),
    enabled: q.length > 0,
    // Resultado de busca não muda em minutos; evita bater no YouTube ao voltar para a tela.
    staleTime: 10 * 60_000,
    retry: false,
  });
}

export function useRecentSessions() {
  return useQuery({
    queryKey: queryKeys.sessionList({ sort: 'newest', limit: 5 }),
    queryFn: ({ signal }) => listSessions({ sort: 'newest', limit: 5 }, signal),
    select: (data) => data.items,
  });
}

export function useDebounced<T>(value: T, ms: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebounced(value);
    }, ms);
    return () => {
      clearTimeout(timer);
    };
  }, [value, ms]);
  return debounced;
}

export function useArtistSuggestions(q: string) {
  const debounced = useDebounced(q.trim(), 200);
  return useQuery({
    queryKey: queryKeys.artists(debounced),
    queryFn: ({ signal }) => searchArtists(debounced, signal),
    placeholderData: keepPreviousData,
    staleTime: 60_000,
  });
}

/** O rascunho foi criado, mas não entrou na fila: quem chamou decide o que oferecer. */
export class DraftKeptError extends Error {
  readonly session: Session;
  readonly cause: unknown;

  constructor(session: Session, cause: unknown) {
    super(cause instanceof Error ? cause.message : String(cause));
    this.name = 'DraftKeptError';
    this.session = session;
    this.cause = cause;
  }
}

export interface Identity {
  artist: string;
  title: string;
}

/** Separar = cria o rascunho com a identidade confirmada e o põe na fila. */
export function useSeparate() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      result,
      identity,
    }: {
      result: SearchResult;
      identity: Identity;
    }): Promise<Job> => {
      const session = await createSession({
        source_url: result.source_url,
        source_title: result.source_title,
        source_channel: result.source_channel,
        duration_s: result.duration_s,
        thumbnail_url: result.thumbnail_url,
        artist: identity.artist,
        title: identity.title,
      });
      try {
        return await processSession(session.id);
      } catch (cause) {
        void queryClient.invalidateQueries({ queryKey: queryKeys.sessionLists });
        throw new DraftKeptError(session, cause);
      }
    },
    onSuccess: (job) => {
      applyNewJob(queryClient, job);
      void queryClient.invalidateQueries({ queryKey: ['artists'] });
    },
  });
}
