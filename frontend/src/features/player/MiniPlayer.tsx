import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router';

import type { Session } from '../../api/types';
import type { AudioEngine } from '../../audio/AudioEngine';
import { player } from '../../audio/player';
import { mixPath } from '../../lib/session';
import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import { Spinner } from '../../ui/Spinner';
import { usePlaybackState, usePlayhead } from '../mixer/hooks';
import { useSession } from '../session/hooks';
import styles from './MiniPlayer.module.css';
import { useMediaSession, usePlayerSnapshot } from './hooks';

/**
 * Barrinha de reprodução do app: aparece fora do mixer enquanto há música no player.
 * Tocar na barra volta ao mixer da sessão. `hidden` (no mixer) só a esconde: o Media Session
 * continua ligado ao player.
 */
export function MiniPlayer({ hidden }: { hidden: boolean }) {
  const { sessionId, engine, error } = usePlayerSnapshot();
  const session = useSession(sessionId ?? '', sessionId !== null).data;
  useMediaSession(engine, session);

  // Não carregou: some, em vez de ficar uma barra morta.
  useEffect(() => {
    if (error) player.close();
  }, [error]);

  if (hidden || !sessionId || error) return null;
  return <Bar sessionId={sessionId} engine={engine} session={session} />;
}

function Bar({
  sessionId,
  engine,
  session,
}: {
  sessionId: string;
  engine: AudioEngine | null;
  session: Session | undefined;
}) {
  const root = useRef<HTMLElement>(null);
  const state = usePlaybackState(engine);
  usePlayhead(engine, root);

  const title = session?.title ?? '';
  const artist = session?.artist ?? '';
  const playing = state === 'playing' || state === 'buffering';
  const loading = engine === null || state === 'loading' || state === 'buffering';

  return (
    <section
      ref={root}
      className={cx(styles.bar, loading && styles.loading)}
      aria-label={strings.player.region}
      aria-busy={loading}
    >
      <Link
        to={mixPath(sessionId)}
        className={styles.open}
        aria-label={strings.player.openMixer(title, artist)}
      >
        <Cover url={session?.thumbnail_url ?? null} />
        <span className={styles.text}>
          <span className={styles.title}>{title}</span>
          <span className={styles.artist}>{artist}</span>
        </span>
      </Link>
      <button
        type="button"
        className={styles.play}
        aria-label={playing ? strings.player.pause : strings.player.play}
        disabled={engine === null}
        onClick={() => {
          engine?.toggle();
        }}
      >
        {state === 'buffering' || engine === null ? (
          <Spinner />
        ) : (
          <Icon name={playing ? 'pause' : 'play_arrow'} filled size={28} />
        )}
      </button>
      <button
        type="button"
        className={styles.close}
        aria-label={strings.player.close}
        onClick={() => {
          player.close();
        }}
      >
        <Icon name="close" size={22} />
      </button>
      <div
        className={styles.progress}
        role="progressbar"
        aria-label={strings.player.progress}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        <div className={styles.fill} />
      </div>
    </section>
  );
}

/** Miniatura da música; sem imagem (ou se falhar), o ícone do app com as 4 barras dos stems. */
function Cover({ url }: { url: string | null }) {
  const [failedUrl, setFailedUrl] = useState<string | null>(null);
  if (url !== null && url !== failedUrl) {
    return (
      <img
        src={url}
        alt=""
        referrerPolicy="no-referrer"
        className={styles.cover}
        onError={() => {
          setFailedUrl(url);
        }}
      />
    );
  }
  return (
    <span className={cx(styles.cover, styles.fallback)} aria-hidden="true">
      <span />
      <span />
      <span />
      <span />
    </span>
  );
}
