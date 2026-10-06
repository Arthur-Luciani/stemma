import { Outlet, useMatch, useMatches } from 'react-router';

import { ProcessingDock } from '../features/processing/ProcessingDock';
import { ProcessingPill } from '../features/processing/ProcessingPill';
import { UpdateBanner } from '../features/update/UpdateNotice';
import { UpdateSheet } from '../features/update/UpdateSheet';
import { ToastProvider } from '../ui/Toast';
import { useIsDesktop } from '../ui/useMediaQuery';
import styles from './AppLayout.module.css';
import { BottomNav, Topbar } from './Navigation';
import type { RouteHandle } from './routes';
import { UpdatePrompt } from './UpdatePrompt';
import { useLiveEvents } from './useLiveEvents';

/** Casca do app: navegação, conteúdo da rota, processamento, aviso de versão nova e toasts. */
export function AppLayout() {
  useLiveEvents();
  const isDesktop = useIsDesktop();
  const fullscreen = useMatches().some((m) => (m.handle as RouteHandle | undefined)?.fullscreen);
  const chrome = isDesktop || !fullscreen;
  // Aviso de versão nova no celular: só no topo do Descobrir e da Biblioteca.
  const onDiscover = useMatch('/') !== null;
  const onLibrary = useMatch('/sessions') !== null;
  const onHome = onDiscover || onLibrary;

  return (
    <ToastProvider>
      <UpdatePrompt />
      <div className={isDesktop ? styles.desktop : fullscreen ? styles.fullscreen : styles.mobile}>
        {isDesktop && <Topbar />}
        {!isDesktop && onHome && <UpdateBanner />}
        <main className={styles.main}>
          <Outlet />
        </main>
        {isDesktop ? <ProcessingDock /> : chrome && <ProcessingPill />}
        {!isDesktop && chrome && <BottomNav />}
      </div>
      <UpdateSheet />
    </ToastProvider>
  );
}
