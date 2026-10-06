import { fireEvent, render } from '@testing-library/react';

import { isTypingTarget, keyToAction, useMixerShortcuts, type ShortcutAction } from './shortcuts';

const key = (code: string, key: string, mods: Partial<KeyboardEvent> = {}) => ({
  code,
  key,
  shiftKey: false,
  ctrlKey: false,
  metaKey: false,
  altKey: false,
  ...mods,
});

describe('keyToAction', () => {
  it('mapeia os atalhos do desktop', () => {
    expect(keyToAction(key('Space', ' '))).toEqual({ type: 'toggle' });
    expect(keyToAction(key('ArrowLeft', 'ArrowLeft'))).toEqual({ type: 'skip', delta: -5 });
    expect(keyToAction(key('ArrowRight', 'ArrowRight'))).toEqual({ type: 'skip', delta: 5 });
    expect(keyToAction(key('Digit1', '1'))).toEqual({ type: 'mute', stem: 'vocals' });
    expect(keyToAction(key('Numpad4', '4'))).toEqual({ type: 'mute', stem: 'other' });
    // Com Shift, `key` vira "@"/"!"; o `code` continua sendo o dígito.
    expect(keyToAction(key('Digit2', '@', { shiftKey: true }))).toEqual({
      type: 'solo',
      stem: 'drums',
    });
    expect(keyToAction(key('KeyA', 'a'))).toEqual({ type: 'markA' });
    expect(keyToAction(key('KeyB', 'B', { shiftKey: true }))).toEqual({ type: 'markB' });
  });

  it('ignora modificadores do sistema e teclas sem atalho', () => {
    expect(keyToAction(key('KeyA', 'a', { ctrlKey: true }))).toBeNull();
    expect(keyToAction(key('Digit1', '1', { metaKey: true }))).toBeNull();
    expect(keyToAction(key('Digit5', '5'))).toBeNull();
    expect(keyToAction(key('KeyC', 'c'))).toBeNull();
  });
});

describe('isTypingTarget', () => {
  it('campos de texto sim; botões e sliders não', () => {
    const text = document.createElement('input');
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    expect(isTypingTarget(text)).toBe(true);
    expect(isTypingTarget(document.createElement('textarea'))).toBe(true);
    expect(isTypingTarget(checkbox)).toBe(false);
    expect(isTypingTarget(document.createElement('button'))).toBe(false);
    expect(isTypingTarget(null)).toBe(false);
  });
});

describe('useMixerShortcuts', () => {
  function Harness({
    onAction,
    enabled = true,
  }: {
    onAction: (a: ShortcutAction) => void;
    enabled?: boolean;
  }) {
    useMixerShortcuts(enabled, onAction);
    return (
      <>
        <input aria-label="campo" />
        <button type="button">botão</button>
        <div role="slider" tabIndex={0} aria-label="fader" aria-valuenow={1} />
        <div role="dialog">
          <button type="button">no diálogo</button>
        </div>
      </>
    );
  }

  it('dispara na janela, mas não em campo de texto, diálogo, repetição ou desligado', () => {
    const onAction = vi.fn();
    const { getByLabelText, getByText, rerender } = render(<Harness onAction={onAction} />);

    fireEvent.keyDown(document.body, { code: 'Space', key: ' ' });
    expect(onAction).toHaveBeenLastCalledWith({ type: 'toggle' });

    fireEvent.keyDown(getByLabelText('campo'), { code: 'KeyA', key: 'a' });
    fireEvent.keyDown(getByText('no diálogo'), { code: 'Space', key: ' ' });
    fireEvent.keyDown(document.body, { code: 'Digit1', key: '1', repeat: true });
    expect(onAction).toHaveBeenCalledOnce();

    fireEvent.keyDown(document.body, { code: 'ArrowRight', key: 'ArrowRight', repeat: true });
    expect(onAction).toHaveBeenLastCalledWith({ type: 'skip', delta: 5 });

    // Espaço num botão é do botão; num slider continua sendo play. Outros atalhos valem.
    fireEvent.keyDown(getByText('botão'), { code: 'Space', key: ' ' });
    expect(onAction).toHaveBeenCalledTimes(2);
    fireEvent.keyDown(getByText('botão'), { code: 'Digit1', key: '1' });
    expect(onAction).toHaveBeenLastCalledWith({ type: 'mute', stem: 'vocals' });
    fireEvent.keyDown(getByLabelText('fader'), { code: 'Space', key: ' ' });
    expect(onAction).toHaveBeenLastCalledWith({ type: 'toggle' });

    rerender(<Harness onAction={onAction} enabled={false} />);
    fireEvent.keyDown(document.body, { code: 'Space', key: ' ' });
    expect(onAction).toHaveBeenCalledTimes(4);
  });
});
