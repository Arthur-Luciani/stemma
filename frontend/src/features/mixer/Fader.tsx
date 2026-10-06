import type { CSSProperties, PointerEvent } from 'react';

import { cx } from '../../ui/cx';
import styles from './Fader.module.css';
import { sliderKeyDown, useDoubleTap } from './slider';

interface FaderProps {
  /** 0–100. */
  value: number;
  onChange: (value: number) => void;
  label: string;
  /** Cor do preenchimento (token, ex.: `var(--stem-vocals)`). */
  color: string;
  orientation?: 'horizontal' | 'vertical';
  /** `compact`: trilho 4px e thumb 16px (desktop); `touch`: trilho 8px e thumb 28px (celular). */
  size?: 'compact' | 'touch';
  /** Duplo toque/clique volta para cá. */
  defaultValue?: number;
  className?: string;
}

const RANGE = { min: 0, max: 100, step: 1, page: 10 };

/** Fader de volume (`role="slider"`): arrasto, teclado e duplo toque = 100%. */
export function Fader({
  value,
  onChange,
  label,
  color,
  orientation = 'horizontal',
  size = 'compact',
  defaultValue = 100,
  className,
}: FaderProps) {
  const doubleTap = useDoubleTap(() => {
    onChange(defaultValue);
  });

  const valueAt = (event: PointerEvent<HTMLDivElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const ratio =
      orientation === 'horizontal'
        ? (event.clientX - rect.left) / rect.width
        : (rect.bottom - event.clientY) / rect.height;
    return Number.isFinite(ratio) ? Math.min(Math.max(ratio, 0), 1) * 100 : value;
  };

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return;
    event.currentTarget.focus();
    if (doubleTap(event.timeStamp)) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    onChange(valueAt(event));
  };

  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    if (!event.currentTarget.hasPointerCapture(event.pointerId)) return;
    onChange(valueAt(event));
  };

  return (
    <div
      role="slider"
      tabIndex={0}
      aria-label={label}
      aria-orientation={orientation}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={value}
      aria-valuetext={`${String(value)}%`}
      className={cx(styles.fader, styles[orientation], styles[size], className)}
      style={{ '--fader-value': value / 100, '--fader-color': color } as CSSProperties}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onKeyDown={(event) => {
        sliderKeyDown(event, value, RANGE, onChange);
      }}
    >
      <span className={styles.track} />
      <span className={styles.fill} />
      <span className={styles.thumb} />
    </div>
  );
}
