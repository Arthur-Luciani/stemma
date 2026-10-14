import { screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';

import { makeDiskUsage } from '../../test/fixtures';
import { renderApp } from '../../test/render';
import { apiError, server } from '../../test/server';

describe('uso de disco em Sobre o Stemma', () => {
  it('mostra stems, exportações, backups e o espaço livre', async () => {
    server.use(
      http.get('*/api/system/disk', () =>
        HttpResponse.json(
          makeDiskUsage({
            stems_bytes: 2_340_000_000,
            exports_bytes: 87_000_000,
            backups_bytes: 300_000,
            free_bytes: 123_400_000_000,
            total_bytes: 500_000_000_000,
            exports_keep: 3,
            backups_keep: 4,
          }),
        ),
      ),
    );
    renderApp('/sessions?atualizacao=1');

    const sheet = await screen.findByRole('dialog', { name: 'Sobre o Stemma' });
    const disk = await within(sheet).findByRole('region', { name: 'Espaço em disco' });
    expect(within(disk).getByText('Stems').nextSibling).toHaveTextContent('2,3 GB');
    expect(within(disk).getByText('Exportações').nextSibling).toHaveTextContent('87,0 MB');
    expect(within(disk).getByText('Backups do banco').nextSibling).toHaveTextContent('300 kB');
    expect(within(disk).getByText('Livre').nextSibling).toHaveTextContent('123,4 GB de 500,0 GB');
    expect(within(disk).getByText(/Ficam as 3 exportações .* os 4 backups/)).toBeInTheDocument();
  });

  it('só consulta o servidor com a tela aberta', async () => {
    let calls = 0;
    server.use(
      http.get('*/api/system/disk', () => {
        calls += 1;
        return HttpResponse.json(makeDiskUsage());
      }),
    );
    renderApp('/sessions');
    await screen.findByRole('heading', { name: 'Biblioteca' });

    expect(calls).toBe(0);
  });

  it('avisa quando não consegue medir', async () => {
    server.use(http.get('*/api/system/disk', () => apiError(500, 'internal_error', 'Erro')));
    renderApp('/sessions?atualizacao=1');

    expect(await screen.findByText(/Não foi possível medir o espaço/)).toBeInTheDocument();
  });
});
