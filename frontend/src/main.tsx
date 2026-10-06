import { QueryClientProvider } from '@tanstack/react-query';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { createBrowserRouter, RouterProvider } from 'react-router';

import './styles/tokens.css';
import './styles/global.css';
import { createQueryClient } from './app/queryClient';
import { RootErrorBoundary } from './app/RouteError';
import { routes } from './app/routes';
import { installStandaloneMode } from './lib/standaloneMode';

const root = document.getElementById('root');
if (!root) throw new Error('Elemento #root não encontrado');

installStandaloneMode();
const queryClient = createQueryClient();
const router = createBrowserRouter(routes);

createRoot(root).render(
  <StrictMode>
    <RootErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </RootErrorBoundary>
  </StrictMode>,
);
