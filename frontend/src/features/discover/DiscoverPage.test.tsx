import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';

import type { SessionCreate } from '../../api/types';
import { makeJob, makeResult, makeSession, sessionList } from '../../test/fixtures';
import { nth } from '../../test/helpers';
import { renderApp } from '../../test/render';
import { apiError, server } from '../../test/server';

const results = [
  makeResult(),
  makeResult({
    source_url: 'https://www.youtube.com/watch?v=live',
    source_title: 'Green Day – Basket Case (Live at Woodstock 1994)',
    duration_s: 225,
  }),
];

function searchReturns(items = results) {
  server.use(http.get('*/api/search', () => HttpResponse.json({ items })));
}

async function search(text: string) {
  await userEvent.type(screen.getByRole('searchbox', { name: 'Buscar música' }), `${text}{Enter}`);
}

describe('Descobrir', () => {
  it('vazio mostra "Continuar de onde parou" com as sessões recentes', async () => {
    const ready = makeSession({ title: 'Do It', artist: 'Nelly Furtado' });
    const draft = makeSession({ title: 'The Trooper', state: 'draft' });
    server.use(http.get('*/api/sessions', () => HttpResponse.json(sessionList([ready, draft]))));
    renderApp('/');
    const recent = await screen.findByRole('region', { name: 'Continuar de onde parou' });
    expect(within(recent).getByRole('link', { name: /Do It/ })).toHaveAttribute(
      'href',
      `/sessions/${ready.id}/mix`,
    );
    expect(within(recent).getByRole('link', { name: /The Trooper/ })).toHaveAttribute(
      'href',
      `/sessions/${draft.id}`,
    );
  });

  it('celular: buscar → escolher → confirmar no sheet → Separar', async () => {
    searchReturns();
    const created: SessionCreate[] = [];
    const session = makeSession({ state: 'draft', code: 'ST-046' });
    server.use(
      http.get('*/api/artists', () =>
        HttpResponse.json([
          { name: 'Green Day', sessions: 3 },
          { name: 'Green River', sessions: 1 },
        ]),
      ),
      http.post('*/api/sessions', async ({ request }) => {
        created.push((await request.json()) as SessionCreate);
        return HttpResponse.json(session, { status: 201 });
      }),
      http.post('*/api/sessions/:id/process', () =>
        HttpResponse.json(
          makeJob({ state: 'queued', position: 1 }, { ...session, state: 'queued' }),
          {
            status: 201,
          },
        ),
      ),
      http.get('*/api/jobs', () =>
        HttpResponse.json({ items: [makeJob({ eta_s: 95 }, { title: 'Tom Sawyer' })] }),
      ),
    );
    const { router } = renderApp('/');

    await search('basket case');
    expect(router.state.location.search).toBe('?q=basket+case');
    const list = await screen.findByRole('list', { name: 'Resultados da busca' });
    expect(screen.getByText('2 resultados · toque para escolher')).toBeInTheDocument();

    await userEvent.click(nth(within(list).getAllByRole('button'), 1));
    const sheet = await screen.findByRole('dialog', { name: 'Confirme artista e título' });
    expect(within(sheet).getByText(/Live at Woodstock/)).toBeInTheDocument();
    expect(within(sheet).getByText('1 job na frente · começa em ~2 min')).toBeInTheDocument();

    // Autocomplete: escolher "Green River" troca o artista.
    const artist = within(sheet).getByRole('combobox', { name: 'Artista' });
    await userEvent.clear(artist);
    await userEvent.type(artist, 'Green');
    const option = await within(sheet).findByRole('option', { name: /Green River/ });
    expect(option).toHaveTextContent('1 sessão');
    await userEvent.click(option);
    expect(artist).toHaveValue('Green River');

    await userEvent.click(within(sheet).getByRole('button', { name: 'Separar' }));
    expect(await screen.findByText('ST-046 entrou na fila')).toBeInTheDocument();
    expect(created).toEqual([
      expect.objectContaining({
        artist: 'Green River',
        title: 'Basket Case',
        source_url: 'https://www.youtube.com/watch?v=live',
      }),
    ]);
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(router.state.location.search).toBe('?q=basket+case');
  });

  it('desktop: card do passo 2 com "já usado"; fila livre começa agora', async () => {
    searchReturns();
    server.use(
      http.get('*/api/artists', () => HttpResponse.json([{ name: 'Green Day', sessions: 3 }])),
    );
    renderApp('/?q=basket', { desktop: true });
    const list = await screen.findByRole('list', { name: 'Resultados da busca' });
    await userEvent.click(nth(within(list).getAllByRole('button'), 0));
    expect(await screen.findByText('Passo 2 de 2')).toBeInTheDocument();
    expect(await screen.findByText('já usado · 3 sessões')).toBeInTheDocument();
    expect(screen.getByText('Fila livre · começa agora')).toBeInTheDocument();
    expect(within(list).getAllByRole('button')[0]).toHaveAttribute('aria-pressed', 'true');
  });

  it('link colado já vem escolhido', async () => {
    searchReturns([makeResult()]);
    renderApp('/?q=https%3A%2F%2Fyoutu.be%2Fabc', { desktop: true });
    expect(await screen.findByText('Passo 2 de 2')).toBeInTheDocument();
  });

  it('se o process falhar, a sessão fica como rascunho com "Continuar"', async () => {
    searchReturns();
    const session = makeSession({ state: 'draft', code: 'ST-050' });
    server.use(
      http.post('*/api/sessions', () => HttpResponse.json(session, { status: 201 })),
      http.post('*/api/sessions/:id/process', () =>
        apiError(409, 'session_not_draft', 'A sessão não é mais um rascunho.'),
      ),
    );
    renderApp('/?q=basket', { desktop: true });
    const list = await screen.findByRole('list', { name: 'Resultados da busca' });
    await userEvent.click(nth(within(list).getAllByRole('button'), 0));
    await userEvent.click(await screen.findByRole('button', { name: 'Separar' }));
    expect(
      await screen.findByText('ST-050 ficou como rascunho. A sessão não é mais um rascunho.'),
    ).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Continuar' })).toHaveAttribute(
      'href',
      `/sessions/${session.id}`,
    );
  });

  it('nenhum resultado', async () => {
    searchReturns([]);
    renderApp('/?q=basket%20cse');
    expect(await screen.findByText('Nada para “basket cse”')).toBeInTheDocument();
  });

  it('YouTube fora do ar → Tentar de novo refaz a busca', async () => {
    let calls = 0;
    server.use(
      http.get('*/api/search', () => {
        calls += 1;
        return calls === 1
          ? apiError(502, 'youtube_unavailable', 'YouTube indisponível.')
          : HttpResponse.json({ items: results });
      }),
    );
    renderApp('/?q=basket');
    expect(await screen.findByText('YouTube indisponível')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Tentar de novo' }));
    expect(await screen.findByRole('list', { name: 'Resultados da busca' })).toBeInTheDocument();
  });

  it('link inválido mostra a mensagem do backend, sem "Tentar de novo"', async () => {
    server.use(
      http.get('*/api/search', () => apiError(422, 'video_unavailable', 'Vídeo indisponível.')),
    );
    renderApp('/?q=https%3A%2F%2Fyoutu.be%2Fx');
    expect(await screen.findByText('Vídeo indisponível.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Tentar de novo' })).not.toBeInTheDocument();
  });
});
