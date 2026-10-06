import { useEffect, useRef } from 'react';

import type { Stem } from '../../api/types';
import type { AudioEngine } from '../../audio/AudioEngine';
import { STEMS } from '../../audio/stems';

/** Passo do −5 s / +5 s. */
export const SKIP_S = 5;

/** Avança/volta `delta` s a partir da posição atual. */
export function skip(engine: AudioEngine, delta: number): void {
  engine.seek(engine.getPosition() + delta);
}

export type ShortcutAction =
  | { type: 'toggle' }
  | { type: 'skip'; delta: number }
  | { type: 'mute'; stem: Stem }
  | { type: 'solo'; stem: Stem }
  | { type: 'markA' }
  | { type: 'markB' };

type KeyLike = Pick<KeyboardEvent, 'key' | 'code' | 'shiftKey' | 'ctrlKey' | 'metaKey' | 'altKey'>;

/**
 * Atalhos do desktop: Espaço play · ← → 5 s · 1–4 mute · ⇧1–4 solo · A/B marcam o loop.
 * Usa `code` nos dígitos e letras: com Shift, `key` vira `!` (e muda com o layout do teclado).
 */
export function keyToAction(event: KeyLike): ShortcutAction | null {
  if (event.ctrlKey || event.metaKey || event.altKey) return null;
  if (event.code === 'Space') return { type: 'toggle' };
  if (event.key === 'ArrowLeft' && !event.shiftKey) return { type: 'skip', delta: -SKIP_S };
  if (event.key === 'ArrowRight' && !event.shiftKey) return { type: 'skip', delta: SKIP_S };
  const digit = /^(?:Digit|Numpad)([1-4])$/.exec(event.code)?.[1];
  if (digit) {
    const stem = STEMS[Number(digit) - 1];
    if (stem) return { type: event.shiftKey ? 'solo' : 'mute', stem };
  }
  if (event.code === 'KeyA') return { type: 'markA' };
  if (event.code === 'KeyB') return { type: 'markB' };
  return null;
}

/** Foco num campo de texto: as teclas são do campo, não do mixer. */
export function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  if (target.isContentEditable) return true;
  if (target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement) return true;
  if (target instanceof HTMLInputElement) {
    return !['button', 'checkbox', 'radio', 'range', 'submit', 'reset'].includes(target.type);
  }
  return false;
}

/** Controle que o Espaço já aciona: botão, rádio, link. */
export function isPressable(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    target.closest('button, a[href], [role="button"], [role="radio"], [role="checkbox"]') !== null
  );
}

/**
 * Liga os atalhos na janela enquanto `enabled`. Sliders e grupos de rádio param a propagação
 * das setas, então elas mexem no controle focado e não no tempo.
 */
export function useMixerShortcuts(
  enabled: boolean,
  onAction: (action: ShortcutAction) => void,
): void {
  const handler = useRef(onAction);
  useEffect(() => {
    handler.current = onAction;
  }, [onAction]);

  useEffect(() => {
    if (!enabled) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || isTypingTarget(event.target)) return;
      // Dentro de um diálogo aberto (editar identidade, export), as teclas são dele.
      if (event.target instanceof Element && event.target.closest('[role="dialog"]')) return;
      const action = keyToAction(event);
      if (!action) return;
      // Espaço num botão (M, S, preset, Exportar) aciona o botão, como no resto da web.
      if (action.type === 'toggle' && isPressable(event.target)) return;
      // Segurar a tecla só repete o ±5 s.
      if (event.repeat && action.type !== 'skip') return;
      event.preventDefault();
      handler.current(action);
    };
    window.addEventListener('keydown', onKeyDown);
    return () => {
      window.removeEventListener('keydown', onKeyDown);
    };
  }, [enabled]);
}
