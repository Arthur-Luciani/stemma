import { setStandalone } from '../test/media';
import { installStandaloneMode } from './standaloneMode';

function contextMenuOn(target: Element): boolean {
  const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true });
  target.dispatchEvent(event);
  return event.defaultPrevented;
}

describe('installStandaloneMode', () => {
  let viewport: HTMLMetaElement;

  beforeEach(() => {
    viewport = document.createElement('meta');
    viewport.name = 'viewport';
    viewport.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
    document.head.append(viewport);
  });

  afterEach(() => {
    viewport.remove();
    document.body.innerHTML = '';
  });

  it('no navegador não muda nada', () => {
    const undo = installStandaloneMode();

    expect(document.documentElement.dataset.standalone).toBeUndefined();
    expect(contextMenuOn(document.body)).toBe(false);
    expect(viewport.content).not.toContain('user-scalable');
    undo();
  });

  it('instalado: marca o html, bloqueia o menu do toque longo e o pinch zoom', () => {
    setStandalone(true);
    document.body.innerHTML =
      '<a href="/x">link</a><img alt="capa" /><input /><textarea></textarea>';

    const undo = installStandaloneMode();

    expect(document.documentElement.dataset.standalone).toBe('');
    expect(contextMenuOn(document.querySelector('a') as Element)).toBe(true);
    expect(contextMenuOn(document.querySelector('img') as Element)).toBe(true);
    expect(contextMenuOn(document.querySelector('input') as Element)).toBe(false);
    expect(contextMenuOn(document.querySelector('textarea') as Element)).toBe(false);
    expect(viewport.content).toBe(
      'width=device-width, initial-scale=1, viewport-fit=cover, maximum-scale=1, user-scalable=no',
    );

    undo();
    expect(document.documentElement.dataset.standalone).toBeUndefined();
    expect(contextMenuOn(document.querySelector('a') as Element)).toBe(false);
    expect(viewport.content).toBe('width=device-width, initial-scale=1, viewport-fit=cover');
  });
});
