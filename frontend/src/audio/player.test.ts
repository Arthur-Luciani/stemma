import { FakeAudioContext, FakeMedia } from '../test/audio';
import { Player } from './player';

function setup() {
  const contexts: FakeAudioContext[] = [];
  const media: FakeMedia[] = [];
  const player = new Player({
    createContext: () => {
      const ctx = new FakeAudioContext();
      contexts.push(ctx);
      return ctx as unknown as AudioContext;
    },
    createAudio: () => {
      const el = new FakeMedia();
      media.push(el);
      return el as unknown as HTMLAudioElement;
    },
  });
  /** Metadados dos 4 stems do engine `index` (0 = primeiro). */
  const loadEngine = async (index: number, duration = 120) => {
    for (const el of media.slice(index * 4, index * 4 + 4)) el.loaded(duration);
    await Promise.resolve();
  };
  return { player, contexts, media, loadEngine };
}

describe('Player', () => {
  it('começa fechado', () => {
    const { player } = setup();
    expect(player.getSnapshot()).toEqual({ sessionId: null, engine: null, error: null });
  });

  it('abre a sessão e só entrega o engine com os 4 stems carregados', async () => {
    const { player, loadEngine } = setup();
    player.open('s1');
    expect(player.getSnapshot()).toMatchObject({ sessionId: 's1', engine: null });
    await loadEngine(0);
    const { engine } = player.getSnapshot();
    expect(engine?.state).toBe('paused');
    expect(engine?.duration).toBe(120);
  });

  it('reabrir a mesma sessão reaproveita o engine, sem recarregar nem cortar', async () => {
    const { player, contexts, loadEngine } = setup();
    player.open('s1');
    await loadEngine(0);
    const engine = player.getSnapshot().engine;
    engine?.play();

    player.open('s1');
    expect(player.getSnapshot().engine).toBe(engine);
    expect(engine?.state).toBe('playing');
    expect(contexts).toHaveLength(1);
    expect(contexts[0]?.state).not.toBe('closed');
  });

  it('abrir outra sessão solta o engine anterior e carrega o novo', async () => {
    const { player, contexts, loadEngine } = setup();
    player.open('s1');
    await loadEngine(0);
    player.open('s2');
    expect(contexts[0]?.state).toBe('closed');
    expect(player.getSnapshot()).toMatchObject({ sessionId: 's2', engine: null });
    await loadEngine(1);
    expect(player.getSnapshot().engine).not.toBeNull();
    expect(contexts[1]?.state).not.toBe('closed');
  });

  it('um carregamento antigo que termina depois da troca é ignorado', async () => {
    const { player, loadEngine } = setup();
    player.open('s1');
    player.open('s2');
    await loadEngine(0);
    expect(player.getSnapshot()).toMatchObject({ sessionId: 's2', engine: null });
  });

  it('fechar para o som e fecha o AudioContext', async () => {
    const { player, contexts, loadEngine } = setup();
    player.open('s1');
    await loadEngine(0);
    player.getSnapshot().engine?.play();
    player.close();
    expect(contexts.every((c) => c.state === 'closed')).toBe(true);
    expect(player.getSnapshot()).toEqual({ sessionId: null, engine: null, error: null });
  });

  it('erro de carga solta o engine, guarda a mensagem e deixa tentar de novo', async () => {
    const { player, contexts, media } = setup();
    player.open('s1');
    media[0]?.fire('error');
    await Promise.resolve();
    expect(player.getSnapshot().error).toMatch(/stem/);
    expect(contexts[0]?.state).toBe('closed');

    player.open('s1');
    expect(player.getSnapshot()).toMatchObject({ sessionId: 's1', error: null });
    expect(contexts).toHaveLength(2);
  });

  it('avisa quem assina a cada mudança', async () => {
    const { player, loadEngine } = setup();
    const listener = vi.fn();
    const off = player.subscribe(listener);
    player.open('s1');
    await loadEngine(0);
    player.close();
    expect(listener).toHaveBeenCalledTimes(3);
    off();
    player.open('s2');
    expect(listener).toHaveBeenCalledTimes(3);
  });
});
