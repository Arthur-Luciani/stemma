import { useRef, useState, type PointerEvent } from 'react';

import { loopFromDrag } from './mixState';

const RULER_STEPS = [5, 10, 15, 30, 60, 120, 300];

/** Marcas da régua (s): o menor passo que dá no máximo `maxTicks` marcas. */
export function rulerTicks(duration: number, maxTicks = 8): number[] {
  if (!(duration > 0)) return [];
  const step =
    RULER_STEPS.find((s) => Math.floor(duration / s) + 1 <= maxTicks) ??
    RULER_STEPS[RULER_STEPS.length - 1] ??
    60;
  const ticks: number[] = [];
  for (let t = 0; t < duration; t += step) ticks.push(t);
  return ticks;
}

/** Movimento (px) a partir do qual o toque vira arrasto de loop, e não seek. */
export const DRAG_THRESHOLD_PX = 8;

interface TimelineGestureOptions {
  duration: number;
  onSeek: (seconds: number) => void;
  /** Sem ele, arrastar não marca loop (só o toque faz seek). */
  onLoop?: (loop: { a: number; b: number }) => void;
}

/**
 * Toque/clique na linha do tempo faz seek; arrastar marca o loop A–B (com prévia enquanto
 * arrasta). Os handlers vão no elemento que cobre a linha do tempo.
 */
export function useTimelineGesture({ duration, onSeek, onLoop }: TimelineGestureOptions) {
  const start = useRef<{ x: number; seconds: number; dragging: boolean } | null>(null);
  const [preview, setPreview] = useState<{ a: number; b: number } | null>(null);

  const secondsAt = (event: PointerEvent<HTMLElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    if (rect.width <= 0) return 0;
    return Math.min(Math.max((event.clientX - rect.left) / rect.width, 0), 1) * duration;
  };

  const handlers = {
    onPointerDown: (event: PointerEvent<HTMLElement>) => {
      if (event.button !== 0 || !(duration > 0)) return;
      event.currentTarget.setPointerCapture(event.pointerId);
      start.current = { x: event.clientX, seconds: secondsAt(event), dragging: false };
    },
    onPointerMove: (event: PointerEvent<HTMLElement>) => {
      const s = start.current;
      if (!s || !onLoop) return;
      if (!s.dragging && Math.abs(event.clientX - s.x) < DRAG_THRESHOLD_PX) return;
      s.dragging = true;
      setPreview(loopFromDrag(s.seconds, secondsAt(event)));
    },
    onPointerUp: (event: PointerEvent<HTMLElement>) => {
      const s = start.current;
      start.current = null;
      setPreview(null);
      if (!s) return;
      if (!s.dragging) {
        onSeek(s.seconds);
        return;
      }
      const loop = loopFromDrag(s.seconds, secondsAt(event));
      if (loop) onLoop?.(loop);
    },
    onPointerCancel: () => {
      start.current = null;
      setPreview(null);
    },
  };

  return { handlers, preview };
}
