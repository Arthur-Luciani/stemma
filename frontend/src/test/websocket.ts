/** WebSocket controlado pelo teste: `open()`, `receive()` e `drop()` simulam o servidor. */
export class FakeWebSocket {
  static instances: FakeWebSocket[] = [];

  readonly url: string;
  onopen: ((event: Event) => void) | null = null;
  onmessage: ((event: MessageEvent) => void) | null = null;
  onclose: ((event: CloseEvent) => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  closed = false;

  constructor(url: string) {
    this.url = url;
    FakeWebSocket.instances.push(this);
  }

  static latest(): FakeWebSocket {
    const socket = FakeWebSocket.instances.at(-1);
    if (!socket) throw new Error('nenhum WebSocket aberto');
    return socket;
  }

  open(): void {
    this.onopen?.(new Event('open'));
  }

  receive(data: unknown): void {
    this.onmessage?.(new MessageEvent('message', { data: JSON.stringify(data) }));
  }

  /** Queda do lado do servidor. */
  drop(): void {
    this.closed = true;
    this.onclose?.(new CloseEvent('close'));
  }

  close(): void {
    this.closed = true;
  }

  send(): void {
    // O cliente não manda nada.
  }
}
