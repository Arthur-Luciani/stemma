import { act, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';

import type { Job } from '../../api/types';
import { makeJob } from '../../test/fixtures';
import { nth } from '../../test/helpers';
import { renderApp } from '../../test/render';
import { server } from '../../test/server';
import { FakeWebSocket } from '../../test/websocket';

function jobsReturn(items: Job[]) {
  server.use(http.get('*/api/jobs', () => HttpResponse.json({ items })));
}

const running = makeJob(
  { eta_s: 40, progress: 62 },
  { title: 'Basket Case', artist: 'Green Day', code: 'ST-043' },
);
const queued = makeJob(
  { state: 'queued', stage: null, position: 1, eta_s: 300, progress: 0 },
  { title: 'Tom Sawyer', artist: 'Rush', state: 'queued', code: 'ST-044' },
);
const failed = makeJob(
  {
    state: 'failed',
    stage: 'downloading',
    eta_s: null,
    error_code: 'youtube_login_required',
    error_message: 'YouTube pediu login. Atualize os cookies.',
  },
  { title: 'Everlong', artist: 'Foo Fighters', state: 'failed', code: 'ST-045' },
);
const done = makeJob(
  { state: 'done', eta_s: null, finished_at: new Date().toISOString() },
  { title: 'Do It', artist: 'Nelly Furtado', state: 'ready', code: 'ST-042' },
);

describe('Processamento', () => {
  it('celular: pílula resume o job atual e abre o sheet com etapas, fila, falha e pronto', async () => {
    jobsReturn([done, failed, queued, running]);
    const { router } = renderApp('/');
    const pill = await screen.findByRole('button', { name: 'Abrir processamento' });
    expect(pill).toHaveTextContent('Separando · Basket Case');
    expect(pill).toHaveTextContent('62% · ~40s');
    expect(pill).toHaveTextContent('+1');

    await userEvent.click(pill);
    expect(router.state.location.search).toBe('?jobs=1');
    const sheet = screen.getByRole('dialog', { name: 'Processamento' });
    const items = within(sheet).getAllByRole('listitem');
    // Ordem: rodando, fila, falhou, pronto.
    expect(items.map((li) => li.textContent)).toEqual([
      expect.stringContaining('Green Day — Basket Case'),
      expect.stringContaining('Rush — Tom Sawyer'),
      expect.stringContaining('Foo Fighters — Everlong'),
      expect.stringContaining('Nelly Furtado — Do It'),
    ]);
    expect(within(nth(items, 0)).getByText('Baixado')).toBeInTheDocument();
    expect(within(nth(items, 0)).getByText('Separando 62%')).toBeInTheDocument();
    expect(within(nth(items, 0)).getByText('~40s restantes')).toBeInTheDocument();
    // O 1º da fila começa quando o job atual terminar.
    expect(within(nth(items, 1)).getByText('Na fila · começa em ~40s')).toBeInTheDocument();
    expect(
      within(nth(items, 2)).getByText('YouTube pediu login. Atualize os cookies.'),
    ).toBeInTheDocument();
    expect(within(nth(items, 3)).getByRole('link', { name: 'Abrir mixer' })).toHaveAttribute(
      'href',
      `/sessions/${done.session_id}/mix`,
    );
  });

  it('Cancelar, Tentar de novo e Descartar chamam as rotas certas', async () => {
    jobsReturn([failed, running]);
    const calls: string[] = [];
    server.use(
      http.delete('*/api/jobs/:id', ({ params }) => {
        calls.push(`cancel ${String(params.id)}`);
        return new HttpResponse(null, { status: 204 });
      }),
      http.post('*/api/jobs/:id/discard', ({ params }) => {
        calls.push(`discard ${String(params.id)}`);
        return new HttpResponse(null, { status: 204 });
      }),
      http.post('*/api/sessions/:id/reprocess', ({ params }) => {
        calls.push(`reprocess ${String(params.id)}`);
        return HttpResponse.json(makeJob({ state: 'queued', position: 1 }), { status: 201 });
      }),
    );
    renderApp('/?jobs=1');
    const sheet = await screen.findByRole('dialog', { name: 'Processamento' });
    await userEvent.click(within(sheet).getByRole('button', { name: 'Cancelar' }));
    await userEvent.click(within(sheet).getByRole('button', { name: 'Tentar de novo' }));
    await userEvent.click(within(sheet).getByRole('button', { name: 'Descartar' }));
    await waitFor(() => {
      expect(calls).toEqual([
        `cancel ${running.id}`,
        `reprocess ${failed.session_id}`,
        `discard ${failed.id}`,
      ]);
    });
  });

  it('desktop: dock recolhido, expande e acompanha o /ws ao vivo', async () => {
    jobsReturn([running]);
    renderApp('/', { desktop: true });
    const dock = await screen.findByRole('region', { name: 'Processamento' });
    expect(dock).toHaveTextContent('Green Day — Basket Case');
    expect(dock).toHaveTextContent('Separando · 62% · ~40s');

    act(() => {
      FakeWebSocket.latest().open();
      FakeWebSocket.latest().receive({
        type: 'job.updated',
        data: { job: { ...running, progress: 90, eta_s: 8 } },
      });
    });
    expect(await within(dock).findByText('Separando · 90% · ~8s')).toBeInTheDocument();

    await userEvent.click(within(dock).getByRole('button', { name: 'Expandir processamento' }));
    const expanded = screen.getByRole('region', { name: 'Processamento' });
    expect(within(expanded).getByRole('heading', { name: 'Processamento' })).toBeInTheDocument();
    expect(within(expanded).getByText('Separando 90%')).toBeInTheDocument();
  });

  it('sem jobs, nada aparece', async () => {
    renderApp('/', { desktop: true });
    await screen.findByRole('heading', { name: 'O que vamos separar hoje?' });
    expect(screen.queryByRole('region', { name: 'Processamento' })).not.toBeInTheDocument();
  });
});
