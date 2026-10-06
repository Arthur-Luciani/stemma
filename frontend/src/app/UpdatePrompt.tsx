import { useEffect } from 'react';
import { useRegisterSW } from 'virtual:pwa-register/react';

import { strings } from '../strings';
import { useToast } from '../ui/toastContext';

/** Com o app aberto por muito tempo (PWA), procura versão nova de hora em hora. */
export const UPDATE_CHECK_MS = 60 * 60 * 1000;

/**
 * Registra o service worker (só o app shell) e avisa quando há versão nova.
 * O SW novo só assume quando o usuário toca em "Recarregar".
 */
export function UpdatePrompt() {
  const toast = useToast();
  const {
    needRefresh: [needRefresh],
    updateServiceWorker,
  } = useRegisterSW({
    onRegisteredSW(_url, registration) {
      if (!registration) return;
      setInterval(() => {
        void registration.update();
      }, UPDATE_CHECK_MS);
    },
  });

  useEffect(() => {
    if (!needRefresh) return;
    toast.show({
      message: strings.pwa.updateAvailable,
      persistent: true,
      action: {
        label: strings.common.reload,
        onClick: () => {
          void updateServiceWorker(true);
        },
      },
    });
  }, [needRefresh, toast, updateServiceWorker]);

  return null;
}
