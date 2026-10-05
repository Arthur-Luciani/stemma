import { FakeWebSocket } from '../test/websocket';
import { backoffDelay, BACKOFF_MAX_MS, LiveConnection, liveUrl } from './live';
import type { LiveEvent } from './types';

const createSocket = (url: string) => new FakeWebSocket(url) as unknown as WebSocket;

describe('LiveConnection', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('entrega eventos válidos e ignora lixo', () => {
    const onEvent = vi.fn();
    const connection = new LiveConnection({ onEvent, url: 'ws://x/ws', createSocket });
    connection.open();
    const socket = FakeWebSocket.latest();
    socket.open();
    const event = { type: 'session.deleted', data: { id: 'abc' } } satisfies LiveEvent;
    socket.receive(event);
    socket.onmessage?.(new MessageEvent('message', { data: 'não é json' }));
    socket.receive({ sem: 'tipo' });
    expect(onEvent).toHaveBeenCalledExactlyOnceWith(event);
    connection.close();
  });

  it('reconecta com backoff e avisa na reconexão', () => {
    const onReconnect = vi.fn();
    const connection = new LiveConnection({
      onEvent: vi.fn(),
      onReconnect,
      url: 'ws://x/ws',
      createSocket,
      random: () => 0.5,
    });
    connection.open();
    FakeWebSocket.latest().open();
    expect(onReconnect).not.toHaveBeenCalled();

    FakeWebSocket.latest().drop();
    expect(FakeWebSocket.instances).toHaveLength(1);
    vi.advanceTimersByTime(999);
    expect(FakeWebSocket.instances).toHaveLength(1);
    vi.advanceTimersByTime(1);
    expect(FakeWebSocket.instances).toHaveLength(2);

    // Caiu de novo antes de abrir: o atraso dobra.
    FakeWebSocket.latest().drop();
    vi.advanceTimersByTime(1_999);
    expect(FakeWebSocket.instances).toHaveLength(2);
    vi.advanceTimersByTime(1);
    FakeWebSocket.latest().open();
    expect(onReconnect).toHaveBeenCalledOnce();
    connection.close();
  });

  it('close() para de reconectar', () => {
    const connection = new LiveConnection({ onEvent: vi.fn(), url: 'ws://x/ws', createSocket });
    connection.open();
    const socket = FakeWebSocket.latest();
    connection.close();
    expect(socket.closed).toBe(true);
    socket.drop();
    vi.advanceTimersByTime(60_000);
    expect(FakeWebSocket.instances).toHaveLength(1);
  });
});

describe('backoff e URL', () => {
  it('cresce até o teto, com jitter de ±20%', () => {
    expect(backoffDelay(0, () => 0.5)).toBe(1_000);
    expect(backoffDelay(3, () => 0.5)).toBe(8_000);
    expect(backoffDelay(20, () => 1)).toBe(BACKOFF_MAX_MS * 1.2);
    expect(backoffDelay(0, () => 0)).toBe(800);
  });

  it('usa wss quando a página é https (Tailscale)', () => {
    expect(liveUrl({ protocol: 'https:', host: 'pc.tail.ts.net:5183' })).toBe(
      'wss://pc.tail.ts.net:5183/ws',
    );
    expect(liveUrl({ protocol: 'http:', host: '127.0.0.1:5183' })).toBe('ws://127.0.0.1:5183/ws');
  });
});
