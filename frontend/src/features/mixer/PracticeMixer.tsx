import { useRef } from 'react';

import { strings } from '../../strings';
import { Button, ButtonLink } from '../../ui/Button';
import { usePlayhead } from './hooks';
import { LoopABControl } from './LoopABControl';
import styles from './MobileMixer.module.css';
import { MixWaveform } from './MixWaveform';
import { PresetSelector } from './PresetSelector';
import { Transport } from './Transport';
import { formatShortClock, type MixerViewProps } from './views';

/**
 * Modo prática (1f), a tela inicial do mixer no celular: feita para ficar na estante a
 * 50–80 cm. "Ajustar" abre as lanes (1e).
 */
export function PracticeMixer({
  session,
  engine,
  peaks,
  mixer,
  duration,
  onAdjust,
}: MixerViewProps & { onAdjust: () => void }) {
  const root = useRef<HTMLDivElement>(null);
  const time = useRef<HTMLSpanElement>(null);
  usePlayhead(engine, root, time, formatShortClock);
  const { state, preset, dispatch } = mixer;

  return (
    <div ref={root} className={styles.screen}>
      <header className={styles.header}>
        <ButtonLink
          to="/sessions"
          variant="ghost"
          icon="chevron_left"
          iconOnly
          label={strings.mixer.back}
        />
        <div className={styles.identity}>
          <h1 className={styles.title}>{session.title}</h1>
          <div className={styles.meta}>{session.artist}</div>
        </div>
        <Button variant="secondary" icon="tune" className={styles.adjust} onClick={onAdjust}>
          {strings.mixer.adjust}
        </Button>
      </header>

      <PresetSelector
        variant="grid"
        className={styles.practicePresets}
        value={preset}
        onChange={(p) => {
          dispatch({ type: 'preset', preset: p });
        }}
      />

      <div className={styles.spacer} />

      <div className={styles.practiceTimeline}>
        <div className={styles.bigTime} aria-label={strings.mixer.time}>
          <span ref={time} className={styles.bigNow}>
            {formatShortClock(0)}
          </span>
          <span className={styles.bigTotal}>{formatShortClock(duration)}</span>
        </div>
        <MixWaveform
          className={styles.practiceWave}
          peaks={peaks}
          stems={state.stems}
          loop={state.loop}
          duration={duration}
          markers
          onSeek={(seconds) => engine?.seek(seconds)}
          onLoop={(loop) => {
            dispatch({ type: 'loop', loop });
          }}
        />
        <LoopABControl
          variant="practice"
          loop={state.loop}
          pendingA={mixer.pendingA}
          onMarkA={() => {
            mixer.markA(engine?.getPosition() ?? 0);
          }}
          onMarkB={() => {
            mixer.markB(engine?.getPosition() ?? 0);
          }}
          onClear={() => {
            dispatch({ type: 'loop', loop: null });
          }}
        />
      </div>

      <Transport engine={engine} variant="practice" className={styles.practiceTransport} />
    </div>
  );
}
