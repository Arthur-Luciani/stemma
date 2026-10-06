/**
 * Quando aberto como app instalado (PWA), tira comportamentos de página do navegador:
 * seleção de texto e menu ao segurar, arrastar imagem e zoom com dois dedos.
 * O CSS correspondente fica em `global.css`, sob `[data-standalone]`.
 */

export const STANDALONE_QUERY = '(display-mode: standalone), (display-mode: fullscreen)';
const NO_ZOOM = 'maximum-scale=1, user-scalable=no';

export function isStandalone(): boolean {
  const iosStandalone = (navigator as Navigator & { standalone?: boolean }).standalone === true;
  return window.matchMedia(STANDALONE_QUERY).matches || iosStandalone;
}

function isEditable(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    target.closest('input, textarea, select, [contenteditable=""], [contenteditable="true"]') !==
      null
  );
}

function blockContextMenu(event: Event) {
  if (!isEditable(event.target)) event.preventDefault();
}

/** Aplica o modo app se estiver instalado. Devolve a função que desfaz (testes). */
export function installStandaloneMode(): () => void {
  if (!isStandalone()) return () => undefined;

  const root = document.documentElement;
  root.dataset.standalone = '';
  document.addEventListener('contextmenu', blockContextMenu);

  const viewport = document.querySelector<HTMLMetaElement>('meta[name="viewport"]');
  const original = viewport?.content;
  if (viewport && original !== undefined && !original.includes('user-scalable')) {
    viewport.content = `${original}, ${NO_ZOOM}`;
  }

  return () => {
    delete root.dataset.standalone;
    document.removeEventListener('contextmenu', blockContextMenu);
    if (viewport && original !== undefined) viewport.content = original;
  };
}
