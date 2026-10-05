import { useQueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';

import { LiveConnection } from '../api/live';
import { createLiveEventHandler } from './applyLiveEvent';

/** Abre um WebSocket no `/ws` enquanto o app estiver montado e mantém o cache ao vivo. */
export function useLiveEvents(): void {
  const queryClient = useQueryClient();

  useEffect(() => {
    const handler = createLiveEventHandler(queryClient);
    const connection = new LiveConnection({ onEvent: handler.handle, onReconnect: handler.resync });
    connection.open();
    return () => {
      connection.close();
      handler.dispose();
    };
  }, [queryClient]);
}
