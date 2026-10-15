import type { PresetStem } from '../../api/types';
import { stemColorVar, STEMS } from '../../audio/stems';
import { formatPan } from './mixState';
import styles from './StemSummary.module.css';
import { presetLevel } from './presetText';
import { stemLabel } from './views';

interface StemSummaryProps {
  stems: Readonly<Record<string, PresetStem | undefined>>;
}

/**
 * Volume (barra), pan (ponto embaixo) e mute (tracejado) dos 4 stems, em ordem fixa.
 * Tem `role="img"` com o texto por extenso.
 */
export function StemSummary({ stems }: StemSummaryProps) {
  const aria = STEMS.map((stem) => {
    const { volume, pan, mute } = presetLevel(stems, stem);
    return `${stemLabel(stem)} ${mute ? 'mudo' : `${String(volume)}%`}, ${formatPan(pan)}`;
  }).join('; ');
  return (
    <div role="img" aria-label={aria} className={styles.summary}>
      {STEMS.map((stem) => {
        const { volume, pan, mute } = presetLevel(stems, stem);
        const color = stemColorVar(stem);
        return (
          <div key={stem} className={styles.cell}>
            <div className={styles.bar}>
              <div
                className={mute ? styles.muted : styles.fill}
                style={{ height: mute ? '100%' : `${String(volume)}%`, '--stem': color } as never}
              />
            </div>
            <div className={styles.pan}>
              <div className={styles.dot} style={{ left: `${String(50 + pan * 50)}%` }} />
            </div>
          </div>
        );
      })}
    </div>
  );
}
