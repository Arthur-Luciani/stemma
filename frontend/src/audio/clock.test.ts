import { MasterClock } from './clock';

describe('MasterClock', () => {
  let now = 0;
  const clock = () => new MasterClock(() => now);

  beforeEach(() => {
    now = 10;
  });

  it('parado, fica na posição', () => {
    const c = clock();
    c.seek(5);
    now = 20;
    expect(c.position).toBe(5);
    expect(c.running).toBe(false);
  });

  it('rodando, avança com o relógio de base', () => {
    const c = clock();
    c.start(2);
    now = 13.5;
    expect(c.position).toBeCloseTo(5.5);
  });

  it('pausa congela e retoma de onde parou', () => {
    const c = clock();
    c.start(0);
    now = 12;
    c.stop();
    now = 100;
    expect(c.position).toBeCloseTo(2);
    c.start();
    now = 101;
    expect(c.position).toBeCloseTo(3);
  });

  it('seek rodando continua rodando a partir do ponto novo', () => {
    const c = clock();
    c.start(0);
    now = 11;
    c.seek(30);
    now = 12;
    expect(c.position).toBeCloseTo(31);
    expect(c.running).toBe(true);
  });
});
