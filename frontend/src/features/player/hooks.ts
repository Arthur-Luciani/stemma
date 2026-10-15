import { useEffect, useSyncExternalStore } from 'react';

import type { Session } from '../../api/types';
import type { AudioEngine } from '../../audio/AudioEngine';
import { player, type PlayerSnapshot } from '../../audio/player';
import { usePlaybackState } from '../mixer/hooks';

export function usePlayerSnapshot(): PlayerSnapshot {
  return useSyncExternalStore(player.subscribe, player.getSnapshot);
}

/**
 * Media Session: título, artista e play/pause na tela de bloqueio e na notificação do
 * Android. Sem suporte (ou sem engine), nada acontece.
 */
export function useMediaSession(engine: AudioEngine | null, session: Session | undefined): void {
  const state = usePlaybackState(engine);
  const title = session?.title;
  const artist = session?.artist;
  const artwork = session?.thumbnail_url;

  useEffect(() => {
    if (!engine || title === undefined || !('mediaSession' in navigator)) return;
    navigator.mediaSession.metadata = new MediaMetadata({
      title,
      artist,
      artwork: artwork ? [{ src: artwork }] : [],
    });
    navigator.mediaSession.setActionHandler('play', () => {
      engine.play();
    });
    navigator.mediaSession.setActionHandler('pause', () => {
      engine.pause();
    });
    return () => {
      navigator.mediaSession.metadata = null;
      navigator.mediaSession.setActionHandler('play', null);
      navigator.mediaSession.setActionHandler('pause', null);
    };
  }, [engine, title, artist, artwork]);

  useEffect(() => {
    if (!engine || !('mediaSession' in navigator)) return;
    navigator.mediaSession.playbackState =
      state === 'playing' || state === 'buffering' ? 'playing' : 'paused';
  }, [engine, state]);
}
