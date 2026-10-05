import { useEffect, useRef, type PointerEvent } from 'react';

import type { Stem } from '../../api/types';
import type { Loop } from '../../audio/mixLogic';
import { cx } from '../../ui/cx';
import { resamplePeaks } from './peaks';
import styles from './Waveform.module.css';

const BAR = 2;
const GAP = 1;

interface WaveformProps {
  peaks: readonly number[] | undefined;
  stem: Stem;
  /** Stem mudo: cor a 30% e waveform tracejada. */
  muted?: boolean;
  duration: number;
  loop?: Loop | null;
  /** Toque/clique na waveform: posição em fração (0–1). */
  onSeek?: (ratio: number) => void;
  className?: string;
}

/**
 * Waveform de um stem desenhada em canvas a partir dos peaks do backend (ADR 0012).
 * Só redesenha quando os peaks, o mute ou o tamanho mudam. O progresso vem da CSS var
 * `--progress` (0–1) de um ancestral, escrita pelo `usePlayhead` sem re-render.
 */
export function Waveform({
  peaks,
  stem,
  muted = false,
  duration,
  loop,
  onSeek,
  className,
}: WaveformProps) {
  const rest = useRef<HTMLCanvasElement>(null);
  const played = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvases = [rest.current, played.current].filter((c) => c !== null);
    if (!peaks || canvases.length === 0) return;
    const redraw = () => {
      for (const canvas of canvases) draw(canvas, peaks, muted);
    };
    redraw();
    if (typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(redraw);
    observer.observe(canvases[0] as HTMLCanvasElement);
    return () => {
      observer.disconnect();
    };
  }, [peaks, muted]);

  const handlePointer = (event: PointerEvent<HTMLDivElement>) => {
    if (!onSeek) return;
    const rect = event.currentTarget.getBoundingClientRect();
    if (rect.width <= 0) return;
    onSeek(Math.min(Math.max((event.clientX - rect.left) / rect.width, 0), 1));
  };

  return (
    <div
      className={cx(styles.wave, styles[stem], muted && styles.muted, className)}
      onPointerDown={handlePointer}
      aria-hidden="true"
    >
      {loop && duration > 0 && (
        <div
          className={styles.loop}
          style={{
            left: `${String((loop.a / duration) * 100)}%`,
            width: `${String(((loop.b - loop.a) / duration) * 100)}%`,
          }}
        />
      )}
      <canvas ref={rest} className={styles.rest} />
      <canvas ref={played} className={styles.played} />
      <div className={styles.playhead} />
    </div>
  );
}

function draw(canvas: HTMLCanvasElement, peaks: readonly number[], muted: boolean): void {
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const { width, height } = canvas.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round(height * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = getComputedStyle(canvas).color;
  const bars = resamplePeaks(peaks, Math.floor(width / (BAR + GAP)));
  bars.forEach((peak, i) => {
    if (muted && i % 3 === 2) return; // tracejado
    const h = Math.max(1, peak * height);
    ctx.fillRect(i * (BAR + GAP), (height - h) / 2, BAR, h);
  });
}
