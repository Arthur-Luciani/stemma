import { fakeAudio, type FakeGain, type FakeMedia, type FakePanner } from '../test/audio';
import { AudioEngine } from './AudioEngine';
import { STEMS } from './stems';

const URLS = {
  vocals: '/v.mp3',
  drums: '/d.mp3',
  bass: '/b.mp3',
  other: '/o.mp3',
};

async function setup(duration = 180) {
  const audio = fakeAudio();
  const engine = new AudioEngine({ ...audio.options, tickMs: 25 });
  const loading = engine.load(URLS, duration);
  for (const el of audio.media) el.loaded(duration);
  await loading;
  const gain = (i: number) => audio.ctx.sources[i]?.outputs[0] as FakeGain;
  const panner = (i: number) => gain(i).outputs[0] as FakePanner;
  const el = (i: number) => audio.media[i] as FakeMedia;
  return { ...audio, engine, gain, panner, el };
}

const flush = () =>
  new Promise<void>((resolve) => {
    queueMicrotask(resolve);
  });

describe('AudioEngine', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('monta source → gain → pan → destino para cada stem', async () => {
    const { ctx, media, gain, panner } = await setup();
    expect(media).toHaveLength(STEMS.length);
    STEMS.forEach((stem, i) => {
      expect(panner(i).outputs[0]).toBe(ctx.destination);
      expect(media[i]?.src).toBe(URLS[stem]);
      expect(gain(i).gain.value).toBe(1);
    });
  });

  it('carrega, pega a duração dos metadados e fica pausado', async () => {
    const { engine } = await setup(200);
    expect(engine.state).toBe('paused');
    expect(engine.duration).toBe(200);
  });

  it('play retoma o contexto no gesto e toca os quatro; pause pausa todos', async () => {
    const { engine, ctx, media } = await setup();
    engine.play();
    expect(ctx.resumeCalls).toBe(1);
    expect(media.every((m) => !m.paused)).toBe(true);
    expect(engine.state).toBe('playing');
    engine.pause();
    expect(media.every((m) => m.paused)).toBe(true);
    await flush();
    expect(engine.state).toBe('paused');
  });

  it('não confunde a própria pausa com uma pausa de fora', async () => {
    const { engine, media } = await setup();
    engine.play();
    engine.pause();
    engine.play();
    await flush();
    expect(engine.state).toBe('playing');
    expect(media.every((m) => !m.paused)).toBe(true);
  });

  it('pausa tudo se um stem for pausado de fora (foco de áudio)', async () => {
    const { engine, media, el } = await setup();
    engine.play();
    el(2).pause();
    await flush();
    expect(engine.state).toBe('paused');
    expect(media.every((m) => m.paused)).toBe(true);
  });

  it('aplica volume, pan, mute e solo como o mixdown', async () => {
    const { engine, gain, panner } = await setup();
    engine.setControl('vocals', { volume: 50, pan: -0.3 });
    expect(gain(0).gain.value).toBe(0.5);
    expect(panner(0).pan.value).toBe(-0.3);
    engine.setControl('drums', { solo: true });
    expect(STEMS.map((_, i) => gain(i).gain.value)).toEqual([0, 1, 0, 0]);
    engine.setControl('drums', { mute: true });
    expect(STEMS.map((_, i) => gain(i).gain.value)).toEqual([0.5, 0, 1, 1]);
  });

  it('corrige drift pequeno pela velocidade e grande com seek', async () => {
    const { engine, media, el } = await setup();
    engine.play();
    for (const m of media) m.currentTime = 10;
    el(1).currentTime = 10.05;
    el(3).currentTime = 10.4;
    const stats = engine.resync();
    expect(stats.drift.drums).toBeCloseTo(0.025);
    expect(el(1).playbackRate).toBe(1);
    expect(el(3).currentTime).toBeCloseTo(10.025);
    expect(stats.seekCorrections).toBe(1);
    expect(stats.spread).toBeCloseTo(0.4);

    el(1).currentTime = 10.1;
    el(3).currentTime = 10;
    expect(engine.resync().rateCorrections).toBe(1);
    expect(el(1).playbackRate).toBeLessThan(1);
  });

  it('volta para A ao passar do B', async () => {
    vi.useFakeTimers();
    const { engine, media, advance } = await setup();
    expect(engine.setLoop(12, 10)).toEqual({ a: 10, b: 12 });
    engine.seek(11.9);
    engine.play();
    advance(0.2);
    vi.advanceTimersByTime(30);
    expect(engine.getPosition()).toBeCloseTo(10);
    expect(media.every((m) => Math.abs(m.currentTime - 10) < 1e-9)).toBe(true);
  });

  it('para todos quando um stem trava e retoma alinhado no mais atrasado', async () => {
    const { engine, media, el } = await setup();
    engine.play();
    media.forEach((m, i) => {
      m.currentTime = i === 2 ? 5 : 5.2;
    });
    el(2).readyState = 2;
    el(2).fire('waiting');
    expect(engine.state).toBe('buffering');
    expect(media.every((m) => m.paused)).toBe(true);
    await flush();
    el(2).readyState = 4;
    el(2).fire('canplay');
    expect(engine.state).toBe('playing');
    expect(media.every((m) => m.currentTime === 5 && !m.paused)).toBe(true);
    expect(engine.stats.stalls).toBe(1);
    await flush();
    expect(engine.state).toBe('playing');
  });

  it('emite ended e para no fim', async () => {
    const { engine, el } = await setup(100);
    const ended = vi.fn();
    engine.on('ended', ended);
    engine.play();
    el(0).ended = true;
    el(0).fire('ended');
    expect(ended).toHaveBeenCalledOnce();
    expect(engine.state).toBe('paused');
    expect(engine.getPosition()).toBe(100);
  });

  it('ao voltar para a aba, retoma o contexto e mede o drift', async () => {
    const { engine, ctx } = await setup();
    engine.play();
    ctx.state = 'suspended';
    const stats = vi.fn();
    engine.on('stats', stats);
    document.dispatchEvent(new Event('visibilitychange'));
    expect(ctx.state).toBe('running');
    expect(stats).toHaveBeenCalledOnce();
  });

  it('dispose solta os stems e fecha o contexto', async () => {
    const { engine, ctx, media } = await setup();
    engine.play();
    engine.dispose();
    expect(ctx.state).toBe('closed');
    expect(media.every((m) => m.src === '' && m.paused)).toBe(true);
    expect(ctx.sources.every((s) => s.disconnected)).toBe(true);
  });
});
