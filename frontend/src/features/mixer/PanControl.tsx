import { useRef, type CSSProperties, type PointerEvent } from 'react';

import { cx } from '../../ui/cx';
import { formatPan } from './mixState';
import styles from './PanControl.module.css';
import { sliderKeyDown, useDoubleTap } from './slider';

interface PanControlProps {
  /** −1 (esquerda) a 1 (direita). */
  value: number;
  onChange: (value: number) => void;
  label: string;
  /** `slider`: centrado com marca no meio (desktop). `knob`: 44px, arrasto vertical (celular). */
  variant?: 'slider' | 'knob';
  className?: string;
}

const RANGE = { min: -100, max: 100, step: 1, page: 10 };
/** Arrasto vertical do knob: pixels para ir do centro até um lado. */
const KNOB_PX = 80;

/** Pan (`role="slider"`, rótulo `C`/`L30`/`R20`): arrasto, teclado e duplo toque = centro. */
export function PanControl({
  value,
  onChange,
  label,
  variant = 'slider',
  className,
}: PanControlProps) {
  const drag = useRef<{ y: number; value: number } | null>(null);
  const percent = Math.round(value * 100);
  const set = (next: number) => {
    onChange(Math.min(Math.max(next, -1), 1));
  };
  const doubleTap = useDoubleTap(() => {
    onChange(0);
  });

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return;
    event.currentTarget.focus();
    if (doubleTap(event.timeStamp)) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    if (variant === 'knob') {
      drag.current = { y: event.clientY, value };
      return;
    }
    const rect = event.currentTarget.getBoundingClientRect();
    if (rect.width > 0) set(((event.clientX - rect.left) / rect.width) * 2 - 1);
  };

  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    if (!event.currentTarget.hasPointerCapture(event.pointerId)) return;
    if (variant === 'knob') {
      if (drag.current) set(drag.current.value + (drag.current.y - event.clientY) / KNOB_PX);
      return;
    }
    const rect = event.currentTarget.getBoundingClientRect();
    if (rect.width > 0) set(((event.clientX - rect.left) / rect.width) * 2 - 1);
  };

  return (
    <div
      role="slider"
      tabIndex={0}
      aria-label={label}
      aria-valuemin={-100}
      aria-valuemax={100}
      aria-valuenow={percent}
      aria-valuetext={formatPan(value)}
      className={cx(styles.pan, styles[variant], className)}
      style={{ '--pan': value } as CSSProperties}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={() => {
        drag.current = null;
      }}
      onKeyDown={(event) => {
        sliderKeyDown(event, percent, RANGE, (next) => {
          set(next / 100);
        });
      }}
    >
      {variant === 'slider' ? (
        <>
          <span className={styles.track} />
          <span className={styles.center} />
          <span className={styles.fill} />
          <span className={styles.thumb} />
        </>
      ) : (
        <span className={styles.dial}>
          <span className={styles.notch} />
        </span>
      )}
    </div>
  );
}
