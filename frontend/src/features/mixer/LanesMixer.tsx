import { useRef } from 'react';

import type { Stem } from '../../api/types';
import { useUrlParam } from '../../app/useUrlParam';
import { STEMS, stemColorVar } from '../../audio/stems';
import { strings } from '../../strings';
import { BottomSheet } from '../../ui/BottomSheet';
import { Button } from '../../ui/Button';
import { cx } from '../../ui/cx';
import { Fader } from './Fader';
import { usePlayhead } from './hooks';
import styles from './MobileMixer.module.css';
import { formatPan } from './mixState';
import { MixWaveform } from './MixWaveform';
import { MuteSoloButton } from './MuteSoloButton';
import { PanControl } from './PanControl';
import { PresetSelector } from './PresetSelector';
import { Transport } from './Transport';
import { formatShortClock, stemLabel, type MixerViewProps } from './views';

const isStem = (value: string | null): value is Stem =>
  value !== null && (STEMS as readonly string[]).includes(value);

/** Lanes compactas (1e): faders longos, M/S sempre visíveis e transport na gaveta. */
export function LanesMixer({
  session,
  engine,
  peaks,
  mixer,
  duration,
  onOpenExport,
  onEdit,
  onBack,
}: MixerViewProps & { onBack: () => void }) {
  const root = useRef<HTMLDivElement>(null);
  const time = useRef<HTMLSpanElement>(null);
  usePlayhead(engine, root, time, formatShortClock);
  const { state, preset, dispatch } = mixer;
  const [panParam, openPan, closePan] = useUrlParam('pan');
  const panStem = isStem(panParam) ? panParam : null;

  return (
    <div ref={root} className={cx(styles.screen, styles.lanesScreen)}>
      <header className={styles.header}>
        <Button
          variant="ghost"
          icon="chevron_left"
          iconOnly
          label={strings.mixer.back}
          onClick={onBack}
        />
        <div className={styles.identity}>
          <h1 className={styles.title}>{session.title}</h1>
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
        <Button
          variant="ghost"
          icon="edit"
          iconOnly
          label={strings.mixer.editIdentity}
          onClick={onEdit}
        />
      </header>

      <PresetSelector
        variant="pills"
        className={styles.pills}
        value={preset}
        onChange={(p) => {
          dispatch({ type: 'preset', preset: p });
        }}
      />

      <div className={styles.laneList}>
        {STEMS.map((stem) => {
          const control = state.stems[stem];
          const name = stemLabel(stem);
          return (
            <section
              key={stem}
              className={cx(styles.laneCard, control.mute && styles.muted)}
              aria-label={name}
            >
              <div className={styles.laneTop}>
                <span className={styles.dot} style={{ background: stemColorVar(stem) }} />
                <h2 className={styles.stemName}>{name}</h2>
                <span className={styles.laneValue}>{control.volume}%</span>
                <button
                  type="button"
                  className={styles.panButton}
                  aria-label={`${strings.mixer.pan(name)}: ${formatPan(control.pan)}`}
                  onClick={() => {
                    openPan(stem);
                  }}
                >
                  {formatPan(control.pan)}
                </button>
                <MuteSoloButton
                  kind="mute"
                  stem={name}
                  active={control.mute}
                  onToggle={() => {
                    dispatch({ type: 'mute', stem });
                  }}
                />
                <MuteSoloButton
                  kind="solo"
                  stem={name}
                  active={control.solo}
                  onToggle={() => {
                    dispatch({ type: 'solo', stem });
                  }}
                />
              </div>
              <Fader
                size="touch"
                className={styles.laneFader}
                value={control.volume}
                label={strings.mixer.volume(name)}
                color={stemColorVar(stem)}
                onChange={(value) => {
                  dispatch({ type: 'volume', stem, value });
                }}
              />
            </section>
          );
        })}
        <p className={styles.hint}>{strings.mixer.adjustHint}</p>
      </div>

      <div className={styles.drawer}>
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
          <span ref={time} className={styles.smallTime} aria-label={strings.mixer.time}>
            {formatShortClock(0)}
          </span>
          <Transport engine={engine} variant="drawer" />
          <span className={cx(styles.smallTime, styles.smallTotal)}>
            {formatShortClock(duration)}
          </span>
        </div>
      </div>

      <BottomSheet
        open={panStem !== null}
        onClose={closePan}
        label={panStem ? strings.mixer.panFine(stemLabel(panStem)) : ''}
      >
        {panStem && (
          <div className={styles.panSheet}>
            <div className={styles.panSheetHead}>
              <h2 className={styles.panSheetTitle}>{strings.mixer.panFine(stemLabel(panStem))}</h2>
              <span className={styles.mono}>{formatPan(state.stems[panStem].pan)}</span>
            </div>
            <PanControl
              className={styles.panSheetSlider}
              value={state.stems[panStem].pan}
              label={strings.mixer.pan(stemLabel(panStem))}
              onChange={(value) => {
                dispatch({ type: 'pan', stem: panStem, value });
              }}
            />
            <Button
              variant="secondary"
              block
              onClick={() => {
                dispatch({ type: 'pan', stem: panStem, value: 0 });
              }}
            >
              {strings.mixer.panCenter}
            </Button>
          </div>
        )}
      </BottomSheet>
    </div>
  );
}
