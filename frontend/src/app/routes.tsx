import type { RouteObject } from 'react-router';

import { DiscoverPage } from '../features/discover/DiscoverPage';
import { LibraryPage } from '../features/library/LibraryPage';
import { MixerPage } from '../features/mixer/MixerPage';
import { SessionPage } from '../features/session/SessionPage';
import { AppLayout } from './AppLayout';
import { NotFound, RouteError } from './RouteError';

/** Página técnica do AudioEngine (F4a): só existe em dev e fica fora do bundle de produção. */
const devRoutes: RouteObject[] = import.meta.env.DEV
  ? [
      {
        path: 'dev/engine',
        lazy: () =>
          import('../features/devEngine/DevEnginePage').then((m) => ({
            Component: m.DevEnginePage,
          })),
      },
    ]
  : [];

/** `handle` das rotas: `fullscreen` esconde a bottom nav e a pílula no celular (mixer). */
export interface RouteHandle {
  fullscreen?: boolean;
}

/** Toda tela tem URL. `:id` é sempre o UUID; o `ST-###` só é exibido. */
export const routes: RouteObject[] = [
  {
    element: <AppLayout />,
    errorElement: <RouteError />,
    children: [
      {
        errorElement: <RouteError />,
        children: [
          { index: true, element: <DiscoverPage /> },
          { path: 'sessions', element: <LibraryPage /> },
          { path: 'sessions/:id', element: <SessionPage /> },
          { path: 'sessions/:id/mix', element: <MixerPage />, handle: { fullscreen: true } },
          ...devRoutes,
          { path: '*', element: <NotFound /> },
        ],
      },
    ],
  },
];
