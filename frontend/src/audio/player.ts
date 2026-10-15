import { stemUrl } from '../api/endpoints';
import type { Stem } from '../api/types';
import { AudioEngine, type EngineOptions } from './AudioEngine';
import { STEMS } from './stems';
import { keepScreenOnWhilePlaying } from './wakeLock';

export interface PlayerSnapshot {
  /** Sessão que está (ou estava sendo carregada) no player; `null` com o player fechado. */
  sessionId: string | null;
  /** Só depois de os 4 stems terem metadados. */
  engine: AudioEngine | null;
  error: string | null;
}

const CLOSED: PlayerSnapshot = { sessionId: null, engine: null, error: null };

/**
 * O player do app: dono do único `AudioEngine`, fora do React ([ADR 0017](../../../docs/decisions/0017-player-global.md)).
 * O mixer só se conecta a ele; sair do mixer não solta o áudio. O engine (e o `AudioContext`)
 * é solto ao fechar o player ou ao abrir outra sessão.
 */
export class Player {
  private snapshot: PlayerSnapshot = CLOSED;
  private readonly listeners = new Set<() => void>();
  private current: { engine: AudioEngine; stopWakeLock: () => void } | null = null;

  constructor(private readonly options: EngineOptions = {}) {}

  readonly subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  readonly getSnapshot = (): PlayerSnapshot => this.snapshot;

  /**
   * Conecta o player à sessão. Se ela já é a atual, não recarrega nada (a música segue de onde
   * está); se é outra, solta o engine anterior e carrega o novo.
   */
  open(sessionId: string): void {
    if (this.snapshot.sessionId === sessionId && this.current) return;
    this.release();

    const engine = new AudioEngine(this.options);
    const stopWakeLock = keepScreenOnWhilePlaying(engine);
    this.current = { engine, stopWakeLock };
    this.set({ sessionId, engine: null, error: null });

    const urls = Object.fromEntries(
      STEMS.map((stem) => [stem, stemUrl(sessionId, stem)]),
    ) as Record<Stem, string>;
    engine.load(urls).then(
      () => {
        if (this.current?.engine === engine) this.set({ sessionId, engine, error: null });
      },
      (error: unknown) => {
        if (this.current?.engine !== engine) return;
        this.release();
        this.set({
          sessionId,
          engine: null,
          error: error instanceof Error ? error.message : String(error),
        });
      },
    );
  }

  /** Para e solta o áudio (fecha o `AudioContext`). */
  close(): void {
    this.release();
    this.set(CLOSED);
  }

  private release(): void {
    const current = this.current;
    this.current = null;
    if (!current) return;
    current.stopWakeLock();
    current.engine.dispose();
  }

  private set(next: PlayerSnapshot): void {
    this.snapshot = next;
    for (const listener of [...this.listeners]) listener();
  }
}

/** Instância única do app. */
export const player = new Player();
