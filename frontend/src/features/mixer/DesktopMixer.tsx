import { useRef } from 'react';

import { STEMS, stemColorVar } from '../../audio/stems';
import { formatClock, formatDuration, formatShortDate } from '../../lib/format';
import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import styles from './DesktopMixer.module.css';
import { ExportPopover } from './ExportPanel';
import { Fader } from './Fader';
import { usePlayhead } from './hooks';
import { LoopABControl } from './LoopABControl';
import { MetricsBadge } from './MetricsBadge';
import { MuteSoloButton } from './MuteSoloButton';
import { formatPan } from './mixState';
import { PanControl } from './PanControl';
import { PresetSelector } from './PresetSelector';
import { useTimelineGesture } from './timeline';
import { TimeRuler } from './TimeRuler';
import { Transport } from './Transport';
import { stemLabel, type MixerViewProps } from './views';
import { Waveform } from './Waveform';

/** Mixer do desktop (1440×900): cabeçalho, transport, régua, 4 lanes e dicas de atalho. */
export function DesktopMixer({
  session,
  engine,
  peaks,
  mixer,
  duration,
  exportOpen,
  onOpenExport,
  onCloseExport,
  onEdit,
}: MixerViewProps) {
  const root = useRef<HTMLDivElement>(null);
  const time = useRef<HTMLSpanElement>(null);
  usePlayhead(engine, root, time);

  const { state, preset, dispatch } = mixer;
  const { handlers, preview } = useTimelineGesture({
    duration,
    onSeek: (seconds) => engine?.seek(seconds),
    onLoop: (loop) => {
      dispatch({ type: 'loop', loop });
    },
  });
  const loop = preview ?? state.loop;
  const position = () => engine?.getPosition() ?? 0;

  return (
    <div ref={root} className={styles.mixer}>
      <header className={styles.header}>
        <div className={styles.identity}>
          <div className={styles.titleRow}>
            <h1 className={styles.title}>{session.title}</h1>
            <Button
              variant="ghost"
              size="sm"
              icon="edit"
              iconOnly
              label={strings.mixer.editIdentity}
              onClick={onEdit}
            />
          </div>
          <div className={styles.meta}>
            {session.artist} ·{' '}
            <span className={styles.mono}>
              {[
                session.code,
                formatDuration(session.duration_s),
                formatShortDate(session.created_at),
              ].join(' · ')}
            </span>
          </div>
        </div>
        <PresetSelector
          value={preset}
          onChange={(p) => {
            dispatch({ type: 'preset', preset: p });
          }}
        />
      </header>

      <div className={styles.transport}>
        <Transport engine={engine} variant="bar" />
        <div className={styles.time} aria-label={strings.mixer.time}>
          <span ref={time}>{formatClock(0)}</span>
          <span className={styles.total}> / {formatClock(duration)}</span>
        </div>
        <span className={styles.divider} />
        <LoopABControl
          variant="bar"
          loop={state.loop}
          pendingA={mixer.pendingA}
          onMarkA={() => {
            mixer.markA(position());
          }}
          onMarkB={() => {
            mixer.markB(position());
          }}
          onClear={() => {
            dispatch({ type: 'loop', loop: null });
          }}
        />
        <MetricsBadge metrics={session.metrics} className={styles.metrics} />
        <span className={styles.divider} />
        <ExportPopover
          session={session}
          mixer={mixer}
          open={exportOpen}
          onOpen={onOpenExport}
          onClose={onCloseExport}
        />
      </div>

      <div className={styles.lanesArea}>
        <TimeRuler duration={duration} className={styles.ruler} />
        <div className={styles.lanes}>
          {STEMS.map((stem) => {
            const control = state.stems[stem];
            const name = stemLabel(stem);
            return (
              <section key={stem} className={styles.lane} aria-label={name}>
                <div className={styles.laneHeader}>
                  <div className={styles.laneTop}>
                    <span className={styles.dot} style={{ background: stemColorVar(stem) }} />
                    <h2 className={styles.stemName}>{name}</h2>
                    <MuteSoloButton
                      kind="mute"
                      size="sm"
                      stem={name}
                      active={control.mute}
                      onToggle={() => {
                        dispatch({ type: 'mute', stem });
                      }}
                    />
                    <MuteSoloButton
                      kind="solo"
                      size="sm"
                      stem={name}
                      active={control.solo}
                      onToggle={() => {
                        dispatch({ type: 'solo', stem });
                      }}
                    />
                  </div>
                  <div className={styles.controlRow}>
                    <span className={styles.controlLabel}>{strings.mixer.vol}</span>
                    <Fader
                      value={control.volume}
                      label={strings.mixer.volume(name)}
                      color={stemColorVar(stem)}
                      onChange={(value) => {
                        dispatch({ type: 'volume', stem, value });
                      }}
                    />
                    <span className={styles.value}>{control.volume}%</span>
                  </div>
                  <div className={styles.controlRow}>
                    <span className={styles.controlLabel}>{strings.mixer.panShort}</span>
                    <PanControl
                      value={control.pan}
                      label={strings.mixer.pan(name)}
                      onChange={(value) => {
                        dispatch({ type: 'pan', stem, value });
                      }}
                    />
                    <span className={styles.value}>{formatPan(control.pan)}</span>
                  </div>
                </div>
                <Waveform
                  className={styles.wave}
                  tone={stem}
                  peaks={peaks[stem]?.peaks}
                  muted={control.mute}
                  duration={duration}
                  playhead={false}
                />
              </section>
            );
          })}
          {/* Loop A–B e playhead atravessam as lanes; clicar faz seek, arrastar marca o loop. */}
          <div className={styles.timeline} {...handlers}>
            {loop && duration > 0 && (
              <div
                className={styles.loop}
                style={{
                  left: `${String((loop.a / duration) * 100)}%`,
                  width: `${String(((loop.b - loop.a) / duration) * 100)}%`,
                }}
              />
            )}
            <div className={styles.playhead} />
          </div>
        </div>
      </div>

      <footer className={styles.hints}>
        {strings.mixer.shortcuts.map(([keys, action]) => (
          <span key={keys}>
            <kbd className={styles.kbd}>{keys}</kbd> {action}
          </span>
        ))}
      </footer>
    </div>
  );
}
