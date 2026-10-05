/**
 * `AudioContext` e `<audio>` falsos para testar o AudioEngine no jsdom (que não toca nada).
 * O tempo só anda quando o teste manda (`advance`).
 */

class FakeParam {
  constructor(public value: number) {}
  setTargetAtTime(value: number): this {
    this.value = value;
    return this;
  }
}

export class FakeNode {
  readonly outputs: unknown[] = [];
  disconnected = false;
  connect<T>(target: T): T {
    this.outputs.push(target);
    return target;
  }
  disconnect(): void {
    this.disconnected = true;
  }
}

export class FakeGain extends FakeNode {
  readonly gain = new FakeParam(1);
}

export class FakePanner extends FakeNode {
  readonly pan = new FakeParam(0);
}

export class FakeSource extends FakeNode {
  constructor(readonly mediaElement: FakeMedia) {
    super();
  }
}

export class FakeAudioContext {
  currentTime = 0;
  state: 'suspended' | 'running' | 'closed' = 'suspended';
  baseLatency = 0.01;
  readonly destination = { name: 'destination' };
  readonly sources: FakeSource[] = [];
  resumeCalls = 0;

  resume(): Promise<void> {
    this.resumeCalls += 1;
    this.state = 'running';
    return Promise.resolve();
  }
  close(): Promise<void> {
    this.state = 'closed';
    return Promise.resolve();
  }
  createMediaElementSource(el: FakeMedia): FakeSource {
    const source = new FakeSource(el);
    this.sources.push(source);
    return source;
  }
  createGain(): FakeGain {
    return new FakeGain();
  }
  createStereoPanner(): FakePanner {
    return new FakePanner();
  }
}

export class FakeMedia extends EventTarget {
  src = '';
  preload = '';
  currentTime = 0;
  duration = NaN;
  playbackRate = 1;
  readyState = 0;
  paused = true;
  ended = false;
  seeking = false;
  error: { message: string } | null = null;
  playCalls = 0;

  play(): Promise<void> {
    this.playCalls += 1;
    this.paused = false;
    return Promise.resolve();
  }
  pause(): void {
    if (this.paused) return;
    this.paused = true;
    // Como no navegador, o evento chega depois.
    queueMicrotask(() => this.dispatchEvent(new Event('pause')));
  }
  load(): void {
    /* nada */
  }
  removeAttribute(name: string): void {
    if (name === 'src') this.src = '';
  }
  /** Simula os metadados chegando. */
  loaded(duration: number, readyState = 4): void {
    this.duration = duration;
    this.readyState = readyState;
    this.dispatchEvent(new Event('loadedmetadata'));
  }
  /** Avança `seconds` de relógio de parede, se estiver tocando. */
  advance(seconds: number): void {
    if (!this.paused) this.currentTime += seconds * this.playbackRate;
  }
  fire(type: string): void {
    this.dispatchEvent(new Event(type));
  }
}

export function fakeAudio() {
  const ctx = new FakeAudioContext();
  const media: FakeMedia[] = [];
  return {
    ctx,
    media,
    options: {
      createContext: () => ctx as unknown as AudioContext,
      createAudio: () => {
        const el = new FakeMedia();
        media.push(el);
        return el as unknown as HTMLAudioElement;
      },
    },
    /** Avança o relógio do contexto e dos `<audio>` que estão tocando. */
    advance: (seconds: number) => {
      ctx.currentTime += seconds;
      for (const el of media) el.advance(seconds);
    },
  };
}
