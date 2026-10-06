import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';

import type { SystemUpdate } from '../../api/types';
import { queryKeys } from '../../app/queryKeys';
import { makeSystemUpdate, makeUpdateRun } from '../../test/fixtures';
import { renderApp } from '../../test/render';
import { server } from '../../test/server';
import { failureText, RECENT_MS, updateView } from './status';

const available = (overrides: Partial<SystemUpdate> = {}) =>
  makeSystemUpdate({
    latest_version: '1.5.1',
    available: true,
    notes: [
      {
        version: '1.5.1',
        sections: [
          { title: 'Novidades', items: ['atualizar pelo app'] },
          { title: 'Correções', items: ['portas no instalador'] },
        ],
      },
    ],
    ...overrides,
  });

function serveStatus(data: SystemUpdate) {
  server.use(http.get('*/api/system/update', () => HttpResponse.json(data)));
}

describe('aviso de versão nova', () => {
  it('sem versão nova não mostra nada', async () => {
    renderApp('/sessions');
    await screen.findByRole('heading', { name: 'Biblioteca' });
    expect(screen.queryByText(/disponível/)).not.toBeInTheDocument();
  });

  it('celular: faixa no topo da Biblioteca abre o sheet com versões e novidades', async () => {
    serveStatus(available());
    const { router } = renderApp('/sessions');

    const text = await screen.findByText('Stemma v1.5.1 disponível');
    const banner = text.closest('[role="status"]') as HTMLElement;
    await userEvent.click(within(banner).getByRole('button', { name: 'Ver' }));

    const sheet = await screen.findByRole('dialog', { name: 'Atualizar o Stemma' });
    expect(router.state.location.search).toBe('?atualizacao=1');
    expect(within(sheet).getByText('v1.5.0')).toBeInTheDocument();
    expect(within(sheet).getByText('v1.5.1')).toBeInTheDocument();
    expect(within(sheet).getByText('atualizar pelo app')).toBeInTheDocument();
    expect(within(sheet).getByText('portas no instalador')).toBeInTheDocument();
    expect(within(sheet).getByText(/fora do ar por ~1 min/)).toBeInTheDocument();

    // Back do Android fecha o sheet.
    await router.navigate(-1);
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
  });

  it('celular: a faixa não aparece fora do Descobrir e da Biblioteca', async () => {
    serveStatus(available());
    const { client } = renderApp('/sessions/x');
    await waitFor(() => {
      expect(client.getQueryData(queryKeys.systemUpdate)).toBeDefined();
    });
    expect(screen.queryByText(/Stemma v1.5.1 disponível/)).not.toBeInTheDocument();
  });

  it('desktop: chip na topbar, Atualizar dispara e passa a acompanhar', async () => {
    serveStatus(available());
    let posted = 0;
    server.use(
      http.post('*/api/system/update', () => {
        posted += 1;
        serveStatus(available({ last_run: makeUpdateRun() }));
        return HttpResponse.json(makeUpdateRun(), { status: 202 });
      }),
    );
    renderApp('/', { desktop: true });

    await userEvent.click(await screen.findByRole('button', { name: 'v1.5.1 disponível' }));
    const dialog = await screen.findByRole('dialog', { name: 'Atualizar o Stemma' });
    await userEvent.click(within(dialog).getByRole('button', { name: 'Atualizar' }));

    expect(await within(dialog).findByText(/Instalando a v1.5.1/)).toBeInTheDocument();
    expect(posted).toBe(1);
    expect(screen.getByRole('button', { name: 'Atualizando…' })).toBeInTheDocument();
  });

  it('com job ativo, Atualizar fica desabilitado e explica', async () => {
    serveStatus(available({ active_jobs: 2 }));
    renderApp('/?atualizacao=1', { desktop: true });

    const dialog = await screen.findByRole('dialog', { name: 'Atualizar o Stemma' });
    expect(within(dialog).getByRole('button', { name: 'Atualizar' })).toBeDisabled();
    expect(within(dialog).getByText(/Há 2 músicas sendo processadas/)).toBeInTheDocument();
  });

  it('instalação sem a tarefa: explica e não oferece o botão', async () => {
    serveStatus(available({ can_update: false }));
    renderApp('/?atualizacao=1', { desktop: true });

    const dialog = await screen.findByRole('dialog', { name: 'Atualizar o Stemma' });
    expect(within(dialog).getByText(/não atualiza pelo app/)).toBeInTheDocument();
    expect(within(dialog).queryByRole('button', { name: 'Atualizar' })).not.toBeInTheDocument();
  });

  it('falha anterior mostra o motivo e que a versão atual continua no ar', async () => {
    serveStatus(
      available({
        last_run: makeUpdateRun({
          state: 'failed',
          message: 'Não foi possível iniciar a atualização: Acesso negado.',
          finished_at: new Date().toISOString(),
        }),
      }),
    );
    renderApp('/?atualizacao=1', { desktop: true });

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Não deu certo');
    expect(alert).toHaveTextContent('Acesso negado. A v1.5.0 continua no ar.');
    expect(screen.getByRole('button', { name: 'Atualizar' })).toBeEnabled();
  });

  it('servidor fora do ar durante a atualização: continua em "Atualizando…"', async () => {
    serveStatus(available({ last_run: makeUpdateRun() }));
    const { client } = renderApp('/?atualizacao=1', { desktop: true });
    const dialog = await screen.findByRole('dialog', { name: 'Atualizar o Stemma' });
    expect(within(dialog).getByText(/Instalando a v1.5.1/)).toBeInTheDocument();

    server.use(http.get('*/api/system/update', () => HttpResponse.error()));
    await client.refetchQueries({ queryKey: queryKeys.systemUpdate });

    expect(within(dialog).getByText(/Instalando a v1.5.1/)).toBeInTheDocument();
  });

  it('terminou: mostra a versão nova', async () => {
    serveStatus(
      makeSystemUpdate({
        current_version: '1.5.1',
        latest_version: '1.5.1',
        last_run: makeUpdateRun({ state: 'succeeded', finished_at: new Date().toISOString() }),
      }),
    );
    renderApp('/?atualizacao=1', { desktop: true });

    expect(await screen.findByText('Stemma atualizado para a v1.5.1.')).toBeInTheDocument();
    expect(screen.queryByText(/disponível/)).not.toBeInTheDocument();
  });
});

describe('updateView', () => {
  it('sucesso antigo vira "está na mais recente"', () => {
    const finished = new Date(Date.now() - RECENT_MS - 1000).toISOString();
    const data = makeSystemUpdate({
      current_version: '1.5.1',
      last_run: makeUpdateRun({ state: 'succeeded', finished_at: finished }),
    });
    expect(updateView(data).kind).toBe('upToDate');
  });

  it('versão mais nova logo depois de atualizar continua aparecendo', () => {
    const data = makeSystemUpdate({
      current_version: '1.5.1',
      latest_version: '1.5.2',
      available: true,
      last_run: makeUpdateRun({ state: 'succeeded', finished_at: new Date().toISOString() }),
    });
    expect(updateView(data)).toEqual({ kind: 'available', target: '1.5.2', lastFailure: null });
  });

  it('sem conseguir consultar o GitHub', () => {
    const data = makeSystemUpdate({ check: 'unavailable', latest_version: null });
    expect(updateView(data).kind).toBe('unknown');
  });

  it('o motivo da falha não repete o "continua no ar"', () => {
    expect(failureText('A v1.5.1 falhou. A v1.5.0 continua no ar.', '1.5.0')).toBe(
      'A v1.5.1 falhou. A v1.5.0 continua no ar.',
    );
    expect(failureText(null, '1.5.0')).toBe('A v1.5.0 continua no ar.');
  });
});
