import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';

import { makeJob, makeSession } from '../../test/fixtures';
import { renderApp } from '../../test/render';
import { server } from '../../test/server';

describe('Detalhe da sessão', () => {
  it('rascunho: confere a identidade, salva se mudou e manda separar', async () => {
    const draft = makeSession({ state: 'draft', code: 'ST-040', title: 'Trooper' });
    const calls: string[] = [];
    server.use(
      http.get('*/api/sessions/:id', () => HttpResponse.json(draft)),
      http.patch('*/api/sessions/:id', async ({ request }) => {
        calls.push(`patch ${JSON.stringify(await request.json())}`);
        return HttpResponse.json({ ...draft, title: 'The Trooper' });
      }),
      http.post('*/api/sessions/:id/process', () => {
        calls.push('process');
        return HttpResponse.json(
          makeJob({ state: 'queued', position: 1 }, { ...draft, state: 'queued' }),
          { status: 201 },
        );
      }),
    );
    renderApp(`/sessions/${draft.id}`);
    const title = await screen.findByLabelText('Título');
    await userEvent.clear(title);
    await userEvent.type(title, 'The Trooper');
    await userEvent.click(screen.getByRole('button', { name: 'Separar' }));
    expect(await screen.findByText('ST-040 entrou na fila')).toBeInTheDocument();
    expect(calls).toEqual([
      `patch ${JSON.stringify({ artist: 'Green Day', title: 'The Trooper' })}`,
      'process',
    ]);
  });

  it('em processamento mostra as etapas do job; falha oferece Tentar de novo', async () => {
    const job = makeJob({ progress: 30 }, { title: 'Basket Case' });
    server.use(
      http.get('*/api/sessions/:id', () => HttpResponse.json(job.session)),
      http.get('*/api/jobs', () => HttpResponse.json({ items: [job] })),
    );
    renderApp(`/sessions/${job.session_id}`);
    expect(await screen.findByText('Separando 30%')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Cancelar' })).toBeInTheDocument();
  });

  it('falhou: mensagem do backend e Tentar de novo', async () => {
    const failed = makeSession({
      state: 'failed',
      error_message: 'YouTube pediu login. Atualize os cookies.',
    });
    let reprocessed = false;
    server.use(
      http.get('*/api/sessions/:id', () => HttpResponse.json(failed)),
      http.post('*/api/sessions/:id/reprocess', () => {
        reprocessed = true;
        return HttpResponse.json(makeJob({ state: 'queued', position: 1 }), { status: 201 });
      }),
    );
    renderApp(`/sessions/${failed.id}`);
    expect(
      await screen.findByText('YouTube pediu login. Atualize os cookies.'),
    ).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Tentar de novo' }));
    await waitFor(() => {
      expect(reprocessed).toBe(true);
    });
  });
});
