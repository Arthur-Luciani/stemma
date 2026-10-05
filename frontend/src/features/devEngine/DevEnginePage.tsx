import { useQuery } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router';

import { listSessions } from '../../api/endpoints';
import type { Stem } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { normalizeLoop, type StemControl } from '../../audio/mixLogic';
import { STEMS } from '../../audio/stems';
import { displayName } from '../../lib/session';
import { strings } from '../../strings';
import { Button } from '../../ui/Button';
import { cx } from '../../ui/cx';
import { useToast } from '../../ui/toastContext';
import {
  useAudioEngine,
  useEngineStats,
  usePeaks,
  usePlaybackState,
  usePlayhead,
} from '../mixer/hooks';
import { Waveform } from '../mixer/Waveform';
import styles from './DevEnginePage.module.css';
import { DriftRecorder, heapMb, type DriftReport } from './recorder';

const t = strings.devEngine;
const READY = { state: ['ready' as const], limit: 50 };

const initialControls = (): Record<Stem, StemControl> =>
  Object.fromEntries(
    STEMS.map((stem) => [stem, { volume: 100, pan: 0, mute: false, solo: false }]),
  ) as Record<Stem, StemControl>;

const ms = (seconds: number) => `${(seconds * 1000).toFixed(1)} ms`;

/** `/dev/engine` (só em dev): controles crus do AudioEngine e medição de sincronia (F4a). */
export function DevEnginePage() {
  const [params, setParams] = useSearchParams();
  const sessionId = params.get('session');
  const sessions = useQuery({
    queryKey: queryKeys.sessionList(READY),
    queryFn: ({ signal }) => listSessions(READY, signal),
  });

  const { engine, error } = useAudioEngine(sessionId);
  const peaks = usePeaks(sessionId);
  const state = usePlaybackState(engine);
  const stats = useEngineStats(engine);
  const lanes = useRef<HTMLDivElement>(null);
  const time = useRef<HTMLSpanElement>(null);
  usePlayhead(engine, lanes, time);

  const [controls, setControls] = useState(initialControls);
  const [loopA, setLoopA] = useState<number | null>(null);
  const [loopB, setLoopB] = useState<number | null>(null);
  const [recorder, setRecorder] = useState<DriftRecorder | null>(null);
  const [report, setReport] = useState<DriftReport | null>(null);
  const toast = useToast();

  const duration = engine?.duration ?? 0;
  const loop = normalizeLoop(loopA, loopB, duration || Infinity);

  useEffect(() => {
    engine?.setMix(controls);
  }, [engine, controls]);

  useEffect(() => {
    engine?.setLoop(loopA, loopB);
  }, [engine, loopA, loopB]);

  // Sair da página (ou trocar o engine) no meio de uma medição solta o listener e o engine.
  useEffect(
    () => () => {
      recorder?.stop();
    },
    [recorder],
  );

  const setControl = (stem: Stem, patch: Partial<StemControl>) => {
    setControls((current) => ({ ...current, [stem]: { ...current[stem], ...patch } }));
  };

  const pickSession = (id: string) => {
    recorder?.stop();
    setRecorder(null);
    setReport(null);
    setLoopA(null);
    setLoopB(null);
    setParams(id ? { session: id } : {}, { replace: true });
  };

  const toggleMeasure = () => {
    if (!engine) return;
    if (recorder) {
      setReport(recorder.stop());
      setRecorder(null);
    } else {
      setReport(null);
      setRecorder(new DriftRecorder(engine));
    }
  };

  const copyReport = () => {
    if (!report) return;
    navigator.clipboard.writeText(JSON.stringify(report, null, 2)).then(
      () => {
        toast.show({ message: t.copied, tone: 'good' });
      },
      () => {
        toast.show({ message: t.copyFailed, tone: 'bad' });
      },
    );
  };

  const playing = state === 'playing' || state === 'buffering';
  const heap = heapMb();

  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <h1 className={styles.title}>{t.title}</h1>
        <p className={styles.hint}>{t.hint}</p>
      </header>

      <label className={styles.field}>
        <span>{t.pickSession}</span>
        <select
          className={styles.select}
          value={sessionId ?? ''}
          onChange={(event) => {
            pickSession(event.target.value);
          }}
        >
          <option value="">{t.choose}</option>
          {sessions.data?.items.map((session) => (
            <option key={session.id} value={session.id}>
              {session.code} · {displayName(session)}
            </option>
          ))}
        </select>
      </label>
      {sessions.data?.items.length === 0 && <p className={styles.hint}>{t.noSessions}</p>}
      {error && <p className={styles.error}>{error}</p>}
      {sessionId && !engine && !error && <p className={styles.hint}>{strings.mixer.loading}</p>}

      {engine && (
        <>
          <section className={styles.transport}>
            <Button
              iconOnly
              icon="replay_5"
              label={strings.mixer.back5}
              onClick={() => {
                engine.seek(engine.getPosition() - 5);
              }}
            />
            <Button
              variant="primary"
              iconOnly
              icon={playing ? 'pause' : 'play_arrow'}
              label={playing ? strings.mixer.pause : strings.mixer.play}
              onClick={() => {
                engine.toggle();
              }}
            />
            <Button
              iconOnly
              icon="forward_5"
              label={strings.mixer.forward5}
              onClick={() => {
                engine.seek(engine.getPosition() + 5);
              }}
            />
            <span className={styles.time}>
              <span ref={time}>0:00.0</span> / {duration.toFixed(1)} s
            </span>
          </section>

          <section className={styles.loopRow}>
            <Button
              size="sm"
              onClick={() => {
                setLoopA(engine.getPosition());
              }}
            >
              {strings.mixer.markA}
            </Button>
            <Button
              size="sm"
              onClick={() => {
                setLoopB(engine.getPosition());
              }}
            >
              {strings.mixer.markB}
            </Button>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => {
                setLoopA(null);
                setLoopB(null);
              }}
            >
              {strings.mixer.clearLoop}
            </Button>
            <span className={styles.mono}>
              {t.loop}: {loop ? `${loop.a.toFixed(1)}–${loop.b.toFixed(1)} s` : t.noLoop}
            </span>
          </section>

          <div ref={lanes} className={styles.lanes}>
            {STEMS.map((stem) => {
              const control = controls[stem];
              const name = strings.stems[stem];
              return (
                <div key={stem} className={styles.lane}>
                  <div className={styles.laneHeader}>
                    <span className={cx(styles.dot, styles[stem])} />
                    <span className={styles.stemName}>{name}</span>
                    <button
                      type="button"
                      className={cx(styles.ms, styles.mute)}
                      aria-pressed={control.mute}
                      aria-label={strings.mixer.mute(name)}
                      onClick={() => {
                        setControl(stem, { mute: !control.mute });
                      }}
                    >
                      M
                    </button>
                    <button
                      type="button"
                      className={cx(styles.ms, styles.solo)}
                      aria-pressed={control.solo}
                      aria-label={strings.mixer.solo(name)}
                      onClick={() => {
                        setControl(stem, { solo: !control.solo });
                      }}
                    >
                      S
                    </button>
                    <input
                      type="range"
                      min={0}
                      max={100}
                      value={control.volume}
                      aria-label={strings.mixer.volume(name)}
                      className={styles.range}
                      onChange={(event) => {
                        setControl(stem, { volume: Number(event.target.value) });
                      }}
                    />
                    <input
                      type="range"
                      min={-1}
                      max={1}
                      step={0.05}
                      value={control.pan}
                      aria-label={strings.mixer.pan(name)}
                      className={styles.range}
                      onChange={(event) => {
                        setControl(stem, { pan: Number(event.target.value) });
                      }}
                    />
                    <span className={styles.mono}>{stats ? ms(stats.drift[stem]) : '—'}</span>
                  </div>
                  <Waveform
                    className={styles.wave}
                    stem={stem}
                    peaks={peaks[stem]?.peaks}
                    muted={control.mute}
                    duration={duration}
                    loop={loop}
                    onSeek={(ratio) => {
                      engine.seek(ratio * duration);
                    }}
                  />
                </div>
              );
            })}
          </div>

          <section className={styles.stats}>
            <dl className={styles.grid}>
              <dt>{t.state}</dt>
              <dd>{t.states[state]}</dd>
              <dt>{t.context}</dt>
              <dd>{engine.contextState}</dd>
              <dt>{t.latency}</dt>
              <dd>{ms(engine.baseLatency)}</dd>
              <dt>{t.spread}</dt>
              <dd>{stats ? ms(stats.spread) : '—'}</dd>
              <dt>{t.clockOffset}</dt>
              <dd>{stats ? ms(stats.clockOffset) : '—'}</dd>
              <dt>{t.corrections}</dt>
              <dd>
                {stats
                  ? `${String(stats.rateCorrections)} / ${String(stats.seekCorrections)}`
                  : '—'}
              </dd>
              <dt>{t.stalls}</dt>
              <dd>{stats?.stalls ?? 0}</dd>
              <dt>{t.heap}</dt>
              <dd>{heap === null ? '—' : `${String(heap)} MB`}</dd>
            </dl>
          </section>

          <section className={styles.measure}>
            <h2 className={styles.subtitle}>{t.measure}</h2>
            <div className={styles.loopRow}>
              <Button variant={recorder ? 'danger' : 'secondary'} onClick={toggleMeasure}>
                {recorder ? t.stopMeasure : t.startMeasure}
              </Button>
              {report && (
                <Button icon="content_copy" onClick={copyReport}>
                  {t.copy}
                </Button>
              )}
            </div>
            {recorder && (
              <p className={styles.hint}>{t.measuring(recorder.elapsed, recorder.count)}</p>
            )}
            {report && <pre className={styles.report}>{JSON.stringify(report, null, 2)}</pre>}
          </section>
        </>
      )}
    </div>
  );
}
