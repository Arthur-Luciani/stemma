import { useQueries, useQuery } from '@tanstack/react-query';
import { useEffect, useState, useSyncExternalStore, type RefObject } from 'react';

import { getPeaks, listExports, stemUrl } from '../../api/endpoints';
import type { Stem, StemPeaks } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { AudioEngine, type EngineStats, type PlaybackState } from '../../audio/AudioEngine';
import { STEMS } from '../../audio/stems';
import { formatClock } from '../../lib/format';

interface EngineHandle {
  engine: AudioEngine | null;
  error: string | null;
}

/**
 * Cria o AudioEngine da sessão e o descarta (fechando o `AudioContext`) ao sair ou trocar
 * de sessão. Devolve o engine só depois de os 4 stems terem metadados.
 */
export function useAudioEngine(sessionId: string | null): EngineHandle {
  const [handle, setHandle] = useState<EngineHandle>({ engine: null, error: null });

  useEffect(() => {
    if (!sessionId) return;
    const engine = new AudioEngine();
    let alive = true;
    const urls = Object.fromEntries(
      STEMS.map((stem) => [stem, stemUrl(sessionId, stem)]),
    ) as Record<Stem, string>;
    engine.load(urls).then(
      () => {
        if (alive) setHandle({ engine, error: null });
      },
      (error: unknown) => {
        if (alive)
          setHandle({
            engine: null,
            error: error instanceof Error ? error.message : String(error),
          });
      },
    );
    return () => {
      alive = false;
      engine.dispose();
      setHandle({ engine: null, error: null });
    };
  }, [sessionId]);

  return handle;
}

const noop = () => undefined;
const unsubscribed = () => noop;

export function usePlaybackState(engine: AudioEngine | null): PlaybackState {
  return useSyncExternalStore(
    engine ? (onChange) => engine.on('state', onChange) : unsubscribed,
    () => engine?.state ?? 'idle',
  );
}

/** Estatísticas de sincronia (mudam ~1×/s, então podem passar pelo React). */
export function useEngineStats(engine: AudioEngine | null): EngineStats | null {
  return useSyncExternalStore(
    engine ? (onChange) => engine.on('stats', onChange) : unsubscribed,
    () => engine?.stats ?? null,
  );
}

/**
 * Playhead por rAF, fora do React: escreve `--progress` (0–1) no `container` e o tempo
 * (`1:12.4`, ou o `format` dado) no `time`, sem re-render.
 */
export function usePlayhead(
  engine: AudioEngine | null,
  container: RefObject<HTMLElement | null>,
  time?: RefObject<HTMLElement | null>,
  format: (seconds: number) => string = formatClock,
): void {
  useEffect(() => {
    if (!engine) return;
    let frame = 0;
    let last = -1;
    const tick = () => {
      const position = engine.getPosition();
      if (position !== last) {
        last = position;
        const duration = engine.duration;
        container.current?.style.setProperty(
          '--progress',
          String(duration > 0 ? position / duration : 0),
        );
        if (time?.current) time.current.textContent = format(position);
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(frame);
    };
  }, [engine, container, time, format]);
}

/** Peaks dos 4 stems (arquivos imutáveis enquanto a sessão não for reprocessada). */
export function usePeaks(sessionId: string | null): Partial<Record<Stem, StemPeaks>> {
  const results = useQueries({
    queries: STEMS.map((stem) => ({
      queryKey: queryKeys.peaks(sessionId ?? '', stem),
      queryFn: ({ signal }: { signal: AbortSignal }) => getPeaks(sessionId ?? '', stem, signal),
      enabled: sessionId !== null,
      staleTime: Infinity,
    })),
  });
  const out: Partial<Record<Stem, StemPeaks>> = {};
  STEMS.forEach((stem, i) => {
    const data = results[i]?.data;
    if (data) out[stem] = data;
  });
  return out;
}

/** Exports da sessão, mais recentes primeiro; o `/ws` (`export.updated`) mantém ao vivo. */
export function useExports(sessionId: string) {
  return useQuery({
    queryKey: queryKeys.exports(sessionId),
    queryFn: ({ signal }) => listExports(sessionId, signal),
  });
}
