/** Folga, em px, entre a pílula ativa e a borda (fica fora do degradê). */
export const PILL_EDGE = 32;

interface Viewport {
  scrollLeft: number;
  clientWidth: number;
  scrollWidth: number;
}

interface Item {
  offsetLeft: number;
  offsetWidth: number;
}

/**
 * `scrollLeft` que deixa a pílula inteira à vista, com `PILL_EDGE` de folga; `null` se ela já
 * está à vista.
 */
export function scrollToShow(view: Viewport, item: Item): number | null {
  const start = item.offsetLeft - PILL_EDGE;
  const end = item.offsetLeft + item.offsetWidth + PILL_EDGE;
  if (start < view.scrollLeft) return Math.max(0, start);
  if (end > view.scrollLeft + view.clientWidth) {
    return Math.min(view.scrollWidth - view.clientWidth, end - view.clientWidth);
  }
  return null;
}

/** Bordas com conteúdo escondido: elas ganham o degradê. */
export function hiddenEdges(view: Viewport): { start: boolean; end: boolean } {
  return {
    start: view.scrollLeft > 1,
    end: view.scrollLeft + view.clientWidth < view.scrollWidth - 1,
  };
}
