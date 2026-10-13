import type { PlaybackState } from './AudioEngine';

/** O que o wake lock precisa do player: o estado e o aviso de mudança. */
export interface PlaybackSource {
  readonly state: PlaybackState;
  on(event: 'state', listener: (state: PlaybackState) => void): () => void;
}

export interface WakeLockEnv {
  /** Sem `wakeLock` (navegador sem suporte ou fora de HTTPS), nada acontece. */
  navigator: { wakeLock?: Pick<WakeLock, 'request'> };
  document: Pick<Document, 'visibilityState' | 'addEventListener' | 'removeEventListener'>;
}

const ACTIVE: ReadonlySet<PlaybackState> = new Set(['playing', 'buffering']);

/**
 * Mantém a tela acesa enquanto o `source` toca (ou carrega no meio da música), como o player
 * do YouTube. Pausado, a tela volta a apagar pelo tempo do sistema.
 *
 * O navegador solta o wake lock sozinho quando a página fica oculta; ao voltar visível com a
 * música tocando, ele é pedido de novo. Falha no pedido (bateria fraca, permissão) não é erro
 * para o usuário. Devolve a função que para de acompanhar e solta o wake lock.
 */
export function keepScreenOnWhilePlaying(
  source: PlaybackSource,
  env: WakeLockEnv = { navigator, document },
): () => void {
  const wakeLock = env.navigator.wakeLock;
  if (!wakeLock) return () => undefined;

  let sentinel: WakeLockSentinel | null = null;
  let requesting = false;
  let stopped = false;

  const wanted = () =>
    !stopped && ACTIVE.has(source.state) && env.document.visibilityState === 'visible';

  const release = () => {
    const current = sentinel;
    sentinel = null;
    current?.release().catch(() => undefined);
  };

  const sync = () => {
    if (!wanted()) {
      release();
      return;
    }
    if (sentinel || requesting) return;
    requesting = true;
    wakeLock.request('screen').then(
      (lock) => {
        requesting = false;
        sentinel = lock;
        // O sistema também solta (página oculta, bateria): o próximo `sync` pede de novo.
        lock.addEventListener('release', () => {
          if (sentinel === lock) sentinel = null;
        });
        // O estado pode ter mudado enquanto o pedido estava em andamento.
        if (!wanted()) release();
      },
      (error: unknown) => {
        requesting = false;
        console.debug('Wake lock recusado; a tela pode apagar.', error);
      },
    );
  };

  const unsubscribe = source.on('state', sync);
  env.document.addEventListener('visibilitychange', sync);
  sync();

  return () => {
    stopped = true;
    unsubscribe();
    env.document.removeEventListener('visibilitychange', sync);
    release();
  };
}
