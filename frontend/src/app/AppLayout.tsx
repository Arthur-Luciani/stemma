import { Outlet } from 'react-router';

import { ProcessingDock } from '../features/processing/ProcessingDock';
import { ProcessingPill } from '../features/processing/ProcessingPill';
import { ToastProvider } from '../ui/Toast';
import { useIsDesktop } from '../ui/useMediaQuery';
import styles from './AppLayout.module.css';
import { BottomNav, Topbar } from './Navigation';
import { useLiveEvents } from './useLiveEvents';

/** Casca do app: navegação, conteúdo da rota, processamento e toasts. */
export function AppLayout() {
  useLiveEvents();
  const isDesktop = useIsDesktop();

  return (
    <ToastProvider>
      <div className={isDesktop ? styles.desktop : styles.mobile}>
        {isDesktop && <Topbar />}
        <main className={styles.main}>
          <Outlet />
        </main>
        {isDesktop ? <ProcessingDock /> : <ProcessingPill />}
        {!isDesktop && <BottomNav />}
      </div>
    </ToastProvider>
  );
}
