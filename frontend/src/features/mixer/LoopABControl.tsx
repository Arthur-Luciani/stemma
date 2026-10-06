import { formatDuration } from '../../lib/format';
import { strings } from '../../strings';
import { cx } from '../../ui/cx';
import { Icon } from '../../ui/Icon';
import styles from './LoopABControl.module.css';

interface LoopABControlProps {
  loop: { a: number; b: number } | null;
  pendingA: number | null;
  onMarkA: () => void;
  onMarkB: () => void;
  onClear: () => void;
  /**
   * `bar`: desktop (botões A e B, intervalo e limpar). `practice`: celular, onde o loop é
   * marcado arrastando na waveform (chip, intervalo e "Limpar").
   */
  variant: 'bar' | 'practice';
  className?: string;
}

const range = (loop: { a: number; b: number }) =>
  `${formatDuration(loop.a)} → ${formatDuration(loop.b)}`;

/** Estado do loop A–B e os controles para marcar e limpar. */
export function LoopABControl({
  loop,
  pendingA,
  onMarkA,
  onMarkB,
  onClear,
  variant,
  className,
}: LoopABControlProps) {
  const status =
    pendingA !== null
      ? strings.mixer.loopWaitingB(formatDuration(pendingA))
      : loop
        ? range(loop)
        : variant === 'practice'
          ? strings.mixer.waveHint
          : strings.mixer.loopOff;

  return (
    <div className={cx(styles.loop, styles[variant], className)}>
      {variant === 'bar' && (
        <>
          <button
            type="button"
            className={styles.mark}
            onClick={onMarkA}
            title={strings.mixer.markA}
          >
            <span className={styles.srOnly}>{strings.mixer.markA}</span>
            <span aria-hidden="true">A</span>
          </button>
          <button
            type="button"
            className={styles.mark}
            onClick={onMarkB}
            title={strings.mixer.markB}
          >
            <span className={styles.srOnly}>{strings.mixer.markB}</span>
            <span aria-hidden="true">B</span>
          </button>
        </>
      )}
      <span className={cx(styles.chip, loop && styles.on)}>
        <Icon name={loop ? 'repeat_on' : 'repeat'} size={18} />
        {strings.mixer.loop}
      </span>
      <span className={styles.range} aria-live="polite">
        {status}
      </span>
      {(loop || pendingA !== null) &&
        (variant === 'bar' ? (
          <button
            type="button"
            className={styles.clearIcon}
            onClick={onClear}
            aria-label={strings.mixer.clearLoop}
            title={strings.mixer.clearLoop}
          >
            <Icon name="close" size={18} />
          </button>
        ) : (
          <button type="button" className={styles.clear} onClick={onClear}>
            {strings.mixer.clear}
          </button>
        ))}
    </div>
  );
}
