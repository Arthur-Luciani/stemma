import type { RouteObject } from 'react-router';

import { DiscoverPage } from '../features/discover/DiscoverPage';
import { LibraryPage } from '../features/library/LibraryPage';
import { MixPlaceholderPage } from '../features/session/MixPlaceholderPage';
import { SessionPage } from '../features/session/SessionPage';
import { AppLayout } from './AppLayout';
import { NotFound, RouteError } from './RouteError';

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
          { path: 'sessions/:id/mix', element: <MixPlaceholderPage /> },
          { path: '*', element: <NotFound /> },
        ],
      },
    ],
  },
];
