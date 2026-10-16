import { hiddenEdges, PILL_EDGE, scrollToShow } from './pillsScroll';

const view = (scrollLeft: number) => ({ scrollLeft, clientWidth: 300, scrollWidth: 800 });

describe('scrollToShow', () => {
  it('não rola quando a pílula já está à vista', () => {
    expect(scrollToShow(view(0), { offsetLeft: 100, offsetWidth: 120 })).toBeNull();
  });

  it('pílula cortada à direita rola até ela aparecer inteira, com folga', () => {
    expect(scrollToShow(view(0), { offsetLeft: 250, offsetWidth: 140 })).toBe(
      250 + 140 + PILL_EDGE - 300,
    );
  });

  it('pílula escondida à esquerda rola para trás, sem passar do início', () => {
    expect(scrollToShow(view(400), { offsetLeft: 200, offsetWidth: 100 })).toBe(200 - PILL_EDGE);
    expect(scrollToShow(view(400), { offsetLeft: 10, offsetWidth: 100 })).toBe(0);
  });

  it('não passa do fim da fileira', () => {
    expect(scrollToShow(view(0), { offsetLeft: 700, offsetWidth: 100 })).toBe(500);
  });
});

describe('hiddenEdges', () => {
  it('marca só as bordas com conteúdo escondido', () => {
    expect(hiddenEdges(view(0))).toEqual({ start: false, end: true });
    expect(hiddenEdges(view(200))).toEqual({ start: true, end: true });
    expect(hiddenEdges(view(500))).toEqual({ start: true, end: false });
    expect(hiddenEdges({ scrollLeft: 0, clientWidth: 300, scrollWidth: 300 })).toEqual({
      start: false,
      end: false,
    });
  });
});
