import { useRef, type KeyboardEvent } from 'react';

/** Dois toques/cliques dentro disso (ms) contam como duplo (volta ao padrão). */
export const DOUBLE_TAP_MS = 300;

interface Range {
  min: number;
  max: number;
  step: number;
  /** Passo de PageUp/PageDown. */
  page: number;
}

/** Teclas do padrão ARIA de slider: devolve o novo valor ou `null` se a tecla não é dele. */
export function sliderKey(
  key: string,
  value: number,
  { min, max, step, page }: Range,
): number | null {
  const clamp = (v: number) => Math.min(Math.max(v, min), max);
  switch (key) {
    case 'ArrowRight':
    case 'ArrowUp':
      return clamp(value + step);
    case 'ArrowLeft':
    case 'ArrowDown':
      return clamp(value - step);
    case 'PageUp':
      return clamp(value + page);
    case 'PageDown':
      return clamp(value - page);
    case 'Home':
      return min;
    case 'End':
      return max;
    default:
      return null;
  }
}

/** `onKeyDown` de um slider: aplica a tecla e impede a rolagem da página. */
export function sliderKeyDown(
  event: KeyboardEvent,
  value: number,
  range: Range,
  onChange: (value: number) => void,
): void {
  const next = sliderKey(event.key, value, range);
  if (next === null) return;
  event.preventDefault();
  // Os atalhos do mixer (setas = ±5 s) não podem rodar junto.
  event.stopPropagation();
  if (next !== value) onChange(next);
}

/** Detecta duplo toque/clique (mouse e toque, pelo `pointerdown`). */
export function useDoubleTap(onDouble: () => void): (timeStamp: number) => boolean {
  const last = useRef(-Infinity);
  return (timeStamp: number) => {
    const double = timeStamp - last.current < DOUBLE_TAP_MS;
    last.current = double ? -Infinity : timeStamp;
    if (double) onDouble();
    return double;
  };
}
