import type { AudioEngine } from '../../audio/AudioEngine';
import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import { usePlaybackState } from './hooks';
import { skip, SKIP_S } from './shortcuts';
import styles from './Transport.module.css';

interface TransportProps {
  engine: AudioEngine | null;
  /**
   * `bar`: barra do desktop (início, −5, play 48, +5). `drawer`: gaveta do 1e (play 68).
   * `practice`: Modo prática (play 104). `console`: paisagem (play 60).
   */
  variant: 'bar' | 'drawer' | 'practice' | 'console';
  className?: string;
}

/** Play/pause e ±5 s. O play chama o engine direto no gesto (exigência do `AudioContext`). */
export function Transport({ engine, variant, className }: TransportProps) {
  const state = usePlaybackState(engine);
  const playing = state === 'playing' || state === 'buffering';
  const disabled = !engine;

  return (
    <div className={cx(styles.transport, styles[variant], className)}>
      {variant === 'bar' && (
        <button
          type="button"
          className={styles.skip}
          aria-label={strings.mixer.toStart}
          title={strings.mixer.toStart}
          disabled={disabled}
          onClick={() => engine?.seek(engine.getLoop()?.a ?? 0)}
        >
          <Icon name="skip_previous" />
        </button>
      )}
      <button
        type="button"
        className={styles.skip}
        aria-label={strings.mixer.back5}
        title={strings.mixer.back5}
        disabled={disabled}
        onClick={() => {
          if (engine) skip(engine, -SKIP_S);
        }}
      >
        <Icon name="replay_5" />
      </button>
      <button
        type="button"
        className={styles.play}
        aria-label={playing ? strings.mixer.pause : strings.mixer.play}
        title={playing ? strings.mixer.pause : strings.mixer.play}
        disabled={disabled}
        onClick={() => engine?.toggle()}
      >
        <Icon name={playing ? 'pause' : 'play_arrow'} filled />
      </button>
      <button
        type="button"
        className={styles.skip}
        aria-label={strings.mixer.forward5}
        title={strings.mixer.forward5}
        disabled={disabled}
        onClick={() => {
          if (engine) skip(engine, SKIP_S);
        }}
      >
        <Icon name="forward_5" />
      </button>
    </div>
  );
}
