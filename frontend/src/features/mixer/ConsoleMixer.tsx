import { useRef } from 'react';

import { STEMS, stemColorVar } from '../../audio/stems';
import { strings } from '../../strings';
import { Button, ButtonLink } from '../../ui/Button';
import { cx } from '../../ui/cx';
import { Fader } from './Fader';
import { usePlayhead } from './hooks';
import styles from './MobileMixer.module.css';
import { MixWaveform } from './MixWaveform';
import { MuteSoloButton } from './MuteSoloButton';
import { PanControl } from './PanControl';
import { PresetSelector } from './PresetSelector';
import { Transport } from './Transport';
import { formatShortClock, stemLabel, type MixerViewProps } from './views';

/** Console em paisagem (1g): 4 strips verticais à esquerda, presets e transport à direita. */
export function ConsoleMixer({
  session,
  engine,
  peaks,
  mixer,
  duration,
  onOpenExport,
}: MixerViewProps) {
  const root = useRef<HTMLDivElement>(null);
  const time = useRef<HTMLSpanElement>(null);
  usePlayhead(engine, root, time, formatShortClock);
  const { state, preset, dispatch } = mixer;

  return (
    <div ref={root} className={styles.console}>
      <div className={styles.strips}>
        {STEMS.map((stem) => {
          const control = state.stems[stem];
          const name = stemLabel(stem);
          return (
            <section
              key={stem}
              className={cx(styles.strip, control.mute && styles.muted)}
              aria-label={name}
            >
              <div className={styles.stripTop}>
                <span className={styles.stripName}>
                  <span className={styles.dotSmall} style={{ background: stemColorVar(stem) }} />
                  {name}
                </span>
                <PanControl
                  variant="knob"
                  value={control.pan}
                  label={strings.mixer.pan(name)}
                  onChange={(value) => {
                    dispatch({ type: 'pan', stem, value });
                  }}
                />
              </div>
              <Fader
                orientation="vertical"
                size="touch"
                className={styles.stripFader}
                value={control.volume}
                label={strings.mixer.volume(name)}
                color={stemColorVar(stem)}
                onChange={(value) => {
                  dispatch({ type: 'volume', stem, value });
                }}
              />
              <span className={styles.stripValue}>{control.volume}%</span>
              <div className={styles.stripButtons}>
                <MuteSoloButton
                  kind="mute"
                  size="wide"
                  stem={name}
                  active={control.mute}
                  onToggle={() => {
                    dispatch({ type: 'mute', stem });
                  }}
                />
                <MuteSoloButton
                  kind="solo"
                  size="wide"
                  stem={name}
                  active={control.solo}
                  onToggle={() => {
                    dispatch({ type: 'solo', stem });
                  }}
                />
              </div>
            </section>
          );
        })}
      </div>

      <div className={styles.consoleSide}>
        <header className={styles.header}>
          <ButtonLink
            to="/sessions"
            variant="ghost"
            icon="chevron_left"
            iconOnly
            label={strings.mixer.back}
          />
          <div className={styles.identity}>
            <h1 className={cx(styles.title, styles.titleSmall)}>{session.title}</h1>
            <div className={styles.meta}>
              {session.artist} · <span className={styles.mono}>{session.code}</span>
            </div>
          </div>
          <Button
            variant="ghost"
            icon="ios_share"
            iconOnly
            label={strings.exports.open}
            onClick={onOpenExport}
          />
        </header>
        <PresetSelector
          variant="pills"
          value={preset}
          onChange={(p) => {
            dispatch({ type: 'preset', preset: p });
          }}
        />
        <div className={styles.spacer} />
        <MixWaveform
          className={styles.drawerWave}
          peaks={peaks}
          stems={state.stems}
          loop={state.loop}
          duration={duration}
          onSeek={(seconds) => engine?.seek(seconds)}
          onLoop={(loop) => {
            dispatch({ type: 'loop', loop });
          }}
        />
        <div className={styles.drawerRow}>
          <span className={styles.smallTime} aria-label={strings.mixer.time}>
            <span ref={time}>{formatShortClock(0)}</span>
            <span className={styles.smallTotal}> / {formatShortClock(duration)}</span>
          </span>
          <Transport engine={engine} variant="console" />
        </div>
      </div>
    </div>
  );
}
