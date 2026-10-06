import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useCallback, useEffect, useRef, useState } from 'react';

import { getMix, saveMix } from '../../api/endpoints';
import type { MixPreset } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { useErrorToast } from '../../app/useErrorToast';
import type { AudioEngine } from '../../audio/AudioEngine';
import {
  fromServer,
  markA,
  markB,
  matchPreset,
  mixerReducer,
  toMixStateIn,
  type MixerAction,
  type MixerState,
} from './mixState';

export const SAVE_DEBOUNCE_MS = 600;

export interface Mixer {
  /** `null` até o mix salvo chegar. */
  state: MixerState | null;
  /** Derivado do mix: o preset que ele bate, ou `custom`. */
  preset: MixPreset;
  loadError: unknown;
  dispatch: (action: MixerAction) => void;
  /** Salva agora o que estiver pendente (ex.: antes de exportar). */
  flush: () => Promise<void>;
  /** A marcado esperando o B (só na tela). */
  pendingA: number | null;
  markA: (position: number) => void;
  markB: (position: number) => void;
}

/**
 * Estado do mixer de **uma** sessão (quem chama troca o `key` ao trocar de sessão).
 * A tela é a verdade enquanto está aberta: cada mudança vai na hora para o AudioEngine e é
 * salva com debounce. O save lê o estado no momento do envio (ref), nunca de uma closure.
 */
export function useMixer(
  sessionId: string,
  engine: AudioEngine | null,
  { debounceMs = SAVE_DEBOUNCE_MS }: { debounceMs?: number } = {},
): Mixer {
  const queryClient = useQueryClient();
  const onError = useErrorToast();

  const query = useQuery({
    queryKey: queryKeys.mix(sessionId),
    queryFn: ({ signal }) => getMix(sessionId, signal),
    staleTime: Infinity,
  });

  const [state, setState] = useState<MixerState | null>(null);
  const [pendingA, setPendingA] = useState<number | null>(null);
  const pendingARef = useRef<number | null>(null);
  const stateRef = useRef<MixerState | null>(null);
  /** Corpo (JSON) do último mix salvo ou carregado: igual a ele não precisa salvar. */
  const savedRef = useRef<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  /** Saves em fila: um de cada vez, na ordem, para o último sempre ganhar no servidor. */
  const chainRef = useRef<Promise<void>>(Promise.resolve());

  // Carrega uma vez; refetch depois disso não atropela o que está na tela.
  useEffect(() => {
    if (!query.data || stateRef.current) return;
    const initial = fromServer(query.data);
    stateRef.current = initial;
    savedRef.current = JSON.stringify(toMixStateIn(initial));
    setState(initial);
  }, [query.data]);

  const save = useCallback(
    ({ keepalive = false }: { keepalive?: boolean } = {}): Promise<void> => {
      if (timerRef.current !== null) {
        clearTimeout(timerRef.current);
        timerRef.current = null;
      }
      const run = async () => {
        const current = stateRef.current;
        if (!current) return;
        const body = toMixStateIn(current);
        const key = JSON.stringify(body);
        if (key === savedRef.current) return;
        try {
          const saved = await saveMix(sessionId, body, { keepalive });
          savedRef.current = key;
          queryClient.setQueryData(queryKeys.mix(sessionId), saved);
        } catch (error) {
          onError(error);
        }
      };
      chainRef.current = chainRef.current.then(run);
      return chainRef.current;
    },
    [sessionId, queryClient, onError],
  );

  const dispatch = useCallback(
    (action: MixerAction) => {
      const current = stateRef.current;
      if (!current) return;
      const next = mixerReducer(current, action);
      stateRef.current = next;
      setState(next);
      // Mexer no loop (limpar, arrastar) descarta um A que esperava o B.
      if (action.type === 'loop' && pendingARef.current !== null) {
        pendingARef.current = null;
        setPendingA(null);
      }
      if (timerRef.current !== null) clearTimeout(timerRef.current);
      timerRef.current = setTimeout(() => {
        timerRef.current = null;
        void save();
      }, debounceMs);
    },
    [save, debounceMs],
  );

  const applyMark = useCallback(
    (mark: { loop: MixerState['loop']; pendingA: number | null }) => {
      if (mark.loop !== stateRef.current?.loop) dispatch({ type: 'loop', loop: mark.loop });
      pendingARef.current = mark.pendingA;
      setPendingA(mark.pendingA);
    },
    [dispatch],
  );

  const onMarkA = useCallback(
    (position: number) => {
      if (stateRef.current) applyMark(markA(position, stateRef.current.loop));
    },
    [applyMark],
  );

  const onMarkB = useCallback(
    (position: number) => {
      if (stateRef.current) applyMark(markB(position, stateRef.current.loop, pendingARef.current));
    },
    [applyMark],
  );

  // Sair da tela, fechar a aba ou mandar o app para o fundo salva o que estiver pendente.
  useEffect(() => {
    const onHide = () => void save({ keepalive: true });
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') onHide();
    };
    window.addEventListener('pagehide', onHide);
    document.addEventListener('visibilitychange', onVisibility);
    return () => {
      window.removeEventListener('pagehide', onHide);
      document.removeEventListener('visibilitychange', onVisibility);
      void save();
    };
  }, [save]);

  const stems = state?.stems;
  const loop = state?.loop;
  useEffect(() => {
    if (engine && stems) engine.setMix(stems);
  }, [engine, stems]);
  useEffect(() => {
    if (engine && loop !== undefined) engine.setLoop(loop?.a ?? null, loop?.b ?? null);
  }, [engine, loop]);

  return {
    state,
    preset: stems ? matchPreset(stems) : 'original',
    loadError: query.error,
    dispatch,
    flush: save,
    pendingA,
    markA: onMarkA,
    markB: onMarkB,
  };
}
