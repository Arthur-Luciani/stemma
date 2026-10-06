import { useMemo } from 'react';

import type { Stem, StemPeaks } from '../../api/types';
import { effectiveGains } from '../../audio/mixLogic';
import { STEMS } from '../../audio/stems';
import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import type { MixerState } from './mixState';
import styles from './MixWaveform.module.css';
import { mixPeaks } from './peaks';
import { useTimelineGesture } from './timeline';
import { Waveform } from './Waveform';

interface MixWaveformProps {
  peaks: Partial<Record<Stem, StemPeaks>>;
  stems: MixerState['stems'];
  loop: MixerState['loop'];
  duration: number;
  onSeek: (seconds: number) => void;
  onLoop: (loop: { a: number; b: number }) => void;
  /** Mostra as etiquetas A e B nas bordas do loop (Modo prática). */
  markers?: boolean;
  className?: string;
}

/**
 * Waveform única do mix (celular): reflete os níveis atuais. Toque faz seek; arrastar marca
 * o loop A–B.
 */
export function MixWaveform({
  peaks,
  stems,
  loop,
  duration,
  onSeek,
  onLoop,
  markers = false,
  className,
}: MixWaveformProps) {
  const mixed = useMemo(() => {
    const byStem: Partial<Record<Stem, readonly number[]>> = {};
    for (const stem of STEMS) {
      const p = peaks[stem];
      if (p) byStem[stem] = p.peaks;
    }
    return mixPeaks(byStem, effectiveGains(stems));
  }, [peaks, stems]);
  const { handlers, preview } = useTimelineGesture({ duration, onSeek, onLoop });
  const shown = preview ?? loop;

  return (
    <div
      className={cx(styles.mix, className)}
      role="group"
      aria-label={strings.mixer.waveform}
      {...handlers}
    >
      <Waveform
        className={styles.wave}
        tone="mix"
        peaks={mixed.length > 0 ? mixed : undefined}
        duration={duration}
        loop={shown}
      />
      {markers && shown && duration > 0 && (
        <>
          <span
            className={styles.marker}
            style={{ left: `${String((shown.a / duration) * 100)}%` }}
          >
            A
          </span>
          <span
            className={styles.marker}
            style={{ left: `${String((shown.b / duration) * 100)}%` }}
          >
            B
          </span>
        </>
      )}
    </div>
  );
}
