import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@testing-library/react';
import type { ReactElement } from 'react';
import { createMemoryRouter, MemoryRouter, RouterProvider } from 'react-router';

import { routes } from '../app/routes';
import { ToastProvider } from '../ui/Toast';
import { setDesktop } from './media';

export function testQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: Infinity }, mutations: { retry: false } },
  });
}

/** App inteiro (rotas reais) numa URL, em celular ou desktop. */
export function renderApp(
  path = '/',
  { desktop = false, client = testQueryClient() }: { desktop?: boolean; client?: QueryClient } = {},
) {
  setDesktop(desktop);
  const router = createMemoryRouter(routes, { initialEntries: [path] });
  const result = render(
    <QueryClientProvider client={client}>
      <RouterProvider router={router} />
    </QueryClientProvider>,
  );
  return { ...result, router, client };
}

/** Um componente com Query, Router e Toast. */
export function renderWithProviders(ui: ReactElement, { client = testQueryClient() } = {}) {
  const result = render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <ToastProvider>{ui}</ToastProvider>
      </MemoryRouter>
    </QueryClientProvider>,
  );
  return { ...result, client };
}
