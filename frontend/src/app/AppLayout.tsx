import { Outlet, useMatches } from 'react-router';

import { ProcessingDock } from '../features/processing/ProcessingDock';
import { ProcessingPill } from '../features/processing/ProcessingPill';
import { ToastProvider } from '../ui/Toast';
import { useIsDesktop } from '../ui/useMediaQuery';
import styles from './AppLayout.module.css';
import { BottomNav, Topbar } from './Navigation';
import type { RouteHandle } from './routes';
import { useLiveEvents } from './useLiveEvents';

/** Casca do app: navegação, conteúdo da rota, processamento e toasts. */
export function AppLayout() {
  useLiveEvents();
  const isDesktop = useIsDesktop();
  const fullscreen = useMatches().some((m) => (m.handle as RouteHandle | undefined)?.fullscreen);
  const chrome = isDesktop || !fullscreen;

  return (
    <ToastProvider>
      <div className={isDesktop ? styles.desktop : fullscreen ? styles.fullscreen : styles.mobile}>
        {isDesktop && <Topbar />}
        <main className={styles.main}>
          <Outlet />
        </main>
        {isDesktop ? <ProcessingDock /> : chrome && <ProcessingPill />}
        {!isDesktop && chrome && <BottomNav />}
      </div>
    </ToastProvider>
  );
}
