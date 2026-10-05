import type { LiveEvent } from './types';

export interface LiveConnectionOptions {
  onEvent: (event: LiveEvent) => void;
  /** Chamado a cada reconexão (não na primeira): eventos podem ter se perdido na queda. */
  onReconnect?: () => void;
  url?: string;
  /** Injetáveis para teste. */
  createSocket?: (url: string) => WebSocket;
  random?: () => number;
}

export const BACKOFF_MIN_MS = 1_000;
export const BACKOFF_MAX_MS = 30_000;

export function liveUrl(location: Pick<Location, 'protocol' | 'host'> = window.location): string {
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${protocol}//${location.host}/ws`;
}

/** Atraso da tentativa `attempt` (0, 1, 2…): exponencial com teto e jitter de ±20%. */
export function backoffDelay(attempt: number, random: () => number = Math.random): number {
  const base = Math.min(BACKOFF_MAX_MS, BACKOFF_MIN_MS * 2 ** attempt);
  return Math.round(base * (0.8 + random() * 0.4));
}

function isLiveEvent(value: unknown): value is LiveEvent {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as { type?: unknown }).type === 'string' &&
    typeof (value as { data?: unknown }).data === 'object'
  );
}

/** Um WebSocket em `/ws`, que reconecta sozinho com backoff até `close()`. */
export class LiveConnection {
  private socket: WebSocket | null = null;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private attempt = 0;
  private connectedOnce = false;
  private closed = false;
  private readonly options: LiveConnectionOptions;

  constructor(options: LiveConnectionOptions) {
    this.options = options;
  }

  open(): void {
    this.closed = false;
    this.connect();
  }

  close(): void {
    this.closed = true;
    if (this.timer !== null) clearTimeout(this.timer);
    this.timer = null;
    const socket = this.socket;
    this.socket = null;
    socket?.close();
  }

  private connect(): void {
    const url = this.options.url ?? liveUrl();
    const socket = this.options.createSocket ? this.options.createSocket(url) : new WebSocket(url);
    this.socket = socket;

    socket.onopen = () => {
      this.attempt = 0;
      if (this.connectedOnce) this.options.onReconnect?.();
      this.connectedOnce = true;
    };
    socket.onmessage = (message: MessageEvent) => {
      let parsed: unknown;
      try {
        parsed = JSON.parse(String(message.data));
      } catch {
        return;
      }
      if (isLiveEvent(parsed)) this.options.onEvent(parsed);
    };
    socket.onclose = () => {
      if (this.socket !== socket || this.closed) return;
      this.socket = null;
      this.scheduleReconnect();
    };
  }

  private scheduleReconnect(): void {
    const delay = backoffDelay(this.attempt, this.options.random);
    this.attempt += 1;
    this.timer = setTimeout(() => {
      this.timer = null;
      if (!this.closed) this.connect();
    }, delay);
  }
}
