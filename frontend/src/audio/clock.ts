/**
 * Relógio mestre do AudioEngine: posição (s) ancorada num relógio monotônico (o
 * `AudioContext.currentTime`). Play, pausa e seek reancoram; ler a posição não custa nada,
 * por isso o playhead (rAF) lê daqui e não dos `<audio>`.
 */
export class MasterClock {
  private anchorTime = 0;
  private anchorPosition = 0;
  private _running = false;

  constructor(private readonly now: () => number) {}

  get running(): boolean {
    return this._running;
  }

  get position(): number {
    if (!this._running) return this.anchorPosition;
    return this.anchorPosition + (this.now() - this.anchorTime);
  }

  start(position = this.position): void {
    this.anchor(position);
    this._running = true;
  }

  stop(): void {
    this.anchor(this.position);
    this._running = false;
  }

  /** Move a posição sem mudar se está rodando. */
  seek(position: number): void {
    this.anchor(position);
  }

  private anchor(position: number): void {
    this.anchorPosition = position;
    this.anchorTime = this.now();
  }
}
