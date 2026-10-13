import type { PlaybackState } from './AudioEngine';
import { keepScreenOnWhilePlaying, type PlaybackSource, type WakeLockEnv } from './wakeLock';

class FakeSource implements PlaybackSource {
  state: PlaybackState = 'paused';
  private readonly listeners = new Set<(state: PlaybackState) => void>();

  on(_event: 'state', listener: (state: PlaybackState) => void) {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  set(state: PlaybackState) {
    this.state = state;
    for (const listener of this.listeners) listener(state);
  }

  get listening() {
    return this.listeners.size;
  }
}

class FakeSentinel extends EventTarget {
  released = false;

  release() {
    if (!this.released) {
      this.released = true;
      this.dispatchEvent(new Event('release'));
    }
    return Promise.resolve();
  }
}

function setup() {
  const source = new FakeSource();
  const doc = new EventTarget() as EventTarget & { visibilityState: DocumentVisibilityState };
  doc.visibilityState = 'visible';
  const sentinels: FakeSentinel[] = [];
  let refuse = false;
  const request = vi.fn(() => {
    if (refuse) return Promise.reject(new Error('NotAllowedError'));
    const sentinel = new FakeSentinel();
    sentinels.push(sentinel);
    return Promise.resolve(sentinel as unknown as WakeLockSentinel);
  });
  const env = { navigator: { wakeLock: { request } }, document: doc } as unknown as WakeLockEnv;
  const held = () => sentinels.filter((s) => !s.released).length;
  const setVisibility = (state: DocumentVisibilityState) => {
    doc.visibilityState = state;
    // Como o navegador: oculta, ele mesmo solta o wake lock.
    if (state === 'hidden') for (const s of sentinels) void s.release();
    doc.dispatchEvent(new Event('visibilitychange'));
  };
  return {
    source,
    env,
    request,
    sentinels,
    held,
    setVisibility,
    refuse: () => {
      refuse = true;
    },
  };
}

const flush = () =>
  new Promise<void>((resolve) => {
    setTimeout(resolve, 0);
  });

describe('keepScreenOnWhilePlaying', () => {
  it('pede o wake lock ao tocar e solta ao pausar', async () => {
    const { source, env, request, held } = setup();
    keepScreenOnWhilePlaying(source, env);
    expect(request).not.toHaveBeenCalled();

    source.set('playing');
    await flush();
    expect(request).toHaveBeenCalledWith('screen');
    expect(held()).toBe(1);

    source.set('paused');
    await flush();
    expect(held()).toBe(0);
  });

  it('mantém o mesmo wake lock entre tocando e carregando', async () => {
    const { source, env, request, held } = setup();
    keepScreenOnWhilePlaying(source, env);
    source.set('playing');
    await flush();
    source.set('buffering');
    source.set('playing');
    await flush();
    expect(request).toHaveBeenCalledTimes(1);
    expect(held()).toBe(1);
  });

  it('já tocando ao começar, pede na hora', async () => {
    const { source, env, held } = setup();
    source.state = 'playing';
    keepScreenOnWhilePlaying(source, env);
    await flush();
    expect(held()).toBe(1);
  });

  it('pede de novo ao voltar visível com a música tocando', async () => {
    const { source, env, request, held, setVisibility } = setup();
    keepScreenOnWhilePlaying(source, env);
    source.set('playing');
    await flush();

    setVisibility('hidden');
    await flush();
    expect(held()).toBe(0);
    expect(request).toHaveBeenCalledTimes(1);

    setVisibility('visible');
    await flush();
    expect(request).toHaveBeenCalledTimes(2);
    expect(held()).toBe(1);
  });

  it('não pede ao voltar visível com a música pausada', async () => {
    const { source, env, request, setVisibility } = setup();
    keepScreenOnWhilePlaying(source, env);
    setVisibility('hidden');
    setVisibility('visible');
    await flush();
    expect(request).not.toHaveBeenCalled();
  });

  it('pausar enquanto o pedido está em andamento solta o wake lock que chegar', async () => {
    const { source, env, held, request } = setup();
    keepScreenOnWhilePlaying(source, env);
    source.set('playing');
    source.set('paused');
    await flush();
    expect(request).toHaveBeenCalledTimes(1);
    expect(held()).toBe(0);
  });

  it('parar solta o wake lock e deixa de acompanhar', async () => {
    const { source, env, request, held, setVisibility } = setup();
    const stop = keepScreenOnWhilePlaying(source, env);
    source.set('playing');
    await flush();

    stop();
    await flush();
    expect(held()).toBe(0);
    expect(source.listening).toBe(0);

    setVisibility('visible');
    source.set('playing');
    await flush();
    expect(request).toHaveBeenCalledTimes(1);
  });

  it('pedido recusado não quebra e é tentado de novo no próximo play', async () => {
    const { source, env, request, refuse } = setup();
    const debug = vi.spyOn(console, 'debug').mockImplementation(() => undefined);
    refuse();
    keepScreenOnWhilePlaying(source, env);
    source.set('playing');
    await flush();
    expect(debug).toHaveBeenCalledTimes(1);

    source.set('paused');
    source.set('playing');
    await flush();
    expect(request).toHaveBeenCalledTimes(2);
    debug.mockRestore();
  });

  it('sem suporte, não faz nada', () => {
    const source = new FakeSource();
    const stop = keepScreenOnWhilePlaying(source, {
      navigator: {},
      document,
    });
    source.set('playing');
    expect(source.listening).toBe(0);
    stop();
  });
});
