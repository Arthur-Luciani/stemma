import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';

import type { SessionPatch } from '../../api/types';
import { makeJob, makeSession, sessionList } from '../../test/fixtures';
import { withText } from '../../test/helpers';
import { renderApp } from '../../test/render';
import { apiError, server } from '../../test/server';

const ready = makeSession({ code: 'ST-042', title: 'Do It', artist: 'Nelly Furtado' });
const separating = makeSession({
  code: 'ST-043',
  title: 'Basket Case',
  state: 'separating',
  progress: 62,
});
const queued = makeSession({
  code: 'ST-044',
  title: 'Tom Sawyer',
  artist: 'Rush',
  state: 'queued',
});
const draft = makeSession({ code: 'ST-040', title: 'The Trooper', state: 'draft' });
const failed = makeSession({ code: 'ST-036', title: 'Everlong', state: 'failed' });
const all = [separating, queued, ready, draft, failed];

function libraryReturns(spy?: (url: URL) => void) {
  server.use(
    http.get('*/api/sessions', ({ request }) => {
      const url = new URL(request.url);
      spy?.(url);
      const states = url.searchParams.getAll('state');
      const items = states.length ? all.filter((s) => states.includes(s.state)) : all;
      return HttpResponse.json({ ...sessionList(items), counts: sessionList(all).counts });
    }),
    http.get('*/api/jobs', () =>
      HttpResponse.json({
        items: [
          makeJob({ state: 'queued', position: 1, stage: null }, { ...queued }),
          makeJob({}, { ...separating }),
        ],
      }),
    ),
  );
}

describe('Biblioteca', () => {
  it('desktop: tabela com chip, posição na fila e ação principal contextual', async () => {
    libraryReturns();
    renderApp('/sessions', { desktop: true });
    const table = await screen.findByRole('table');
    expect(screen.getByText('5 sessões')).toBeInTheDocument();
    const rows = within(table).getAllByRole('row').slice(1);
    const row = (code: string) => withText(rows, code);

    expect(within(row('ST-043')).getByText('Separando 62%')).toBeInTheDocument();
    expect(within(row('ST-044')).getByText('Na fila · 1º')).toBeInTheDocument();
    expect(within(row('ST-042')).getByRole('link', { name: 'Abrir mixer' })).toHaveAttribute(
      'href',
      `/sessions/${ready.id}/mix`,
    );
    expect(within(row('ST-043')).getByRole('link', { name: 'Acompanhar' })).toHaveAttribute(
      'href',
      `/sessions/${separating.id}`,
    );
    expect(within(row('ST-040')).getByRole('link', { name: 'Continuar' })).toBeInTheDocument();
    expect(
      within(row('ST-036')).getByRole('button', { name: 'Tentar de novo' }),
    ).toBeInTheDocument();
  });

  it('filtro "Em andamento" mostra a contagem e manda os 3 estados; a URL guarda o filtro', async () => {
    const seen: string[][] = [];
    libraryReturns((url) => seen.push(url.searchParams.getAll('state')));
    const { router } = renderApp('/sessions', { desktop: true });
    const active = await screen.findByRole('radio', { name: 'Em andamento · 2' });
    await userEvent.click(active);
    await waitFor(() => {
      expect(seen.at(-1)).toEqual(['queued', 'downloading', 'separating']);
    });
    expect(router.state.location.search).toBe('?f=active');
    await waitFor(() => {
      expect(within(screen.getByRole('table')).getAllByRole('row')).toHaveLength(3);
    });
  });

  it('busca com debounce vai para a URL; "/" foca a busca no desktop', async () => {
    const seen: (string | null)[] = [];
    libraryReturns((url) => seen.push(url.searchParams.get('q')));
    const { router } = renderApp('/sessions', { desktop: true });
    await screen.findByRole('table');
    await userEvent.keyboard('/');
    const input = screen.getByRole('searchbox', { name: 'Buscar na biblioteca' });
    expect(input).toHaveFocus();
    await userEvent.type(input, 'queen');
    await waitFor(
      () => {
        expect(router.state.location.search).toBe('?q=queen');
        // O GET com a busca sai depois da troca de URL: espera por ele também.
        expect(seen.at(-1)).toBe('queen');
      },
      { timeout: 3000 },
    );
  });

  it('regressão: pausar depois de um espaço não come o espaço do campo', async () => {
    libraryReturns();
    const { router } = renderApp('/sessions', { desktop: true });
    await screen.findByRole('table');
    const input = screen.getByRole('searchbox', { name: 'Buscar na biblioteca' });
    await userEvent.type(input, 'the ');
    await waitFor(
      () => {
        expect(router.state.location.search).toBe('?q=the');
      },
      { timeout: 3000 },
    );
    expect(input).toHaveValue('the ');
    await userEvent.type(input, 'b');
    expect(input).toHaveValue('the b');
  });

  it('regressão: Reprocessar pelo sheet do celular fecha o sheet', async () => {
    libraryReturns();
    server.use(
      http.post('*/api/sessions/:id/reprocess', () =>
        HttpResponse.json(makeJob({ state: 'queued', position: 1 }, ready), { status: 201 }),
      ),
    );
    const { router } = renderApp('/sessions');
    await userEvent.click(await screen.findByRole('button', { name: 'Mais ações: Do It' }));
    const sheet = screen.getByRole('dialog', { name: 'Do It' });
    await userEvent.click(within(sheet).getByRole('button', { name: 'Reprocessar' }));
    expect(await screen.findByText('ST-042 voltou para a fila')).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
    expect(router.state.location.search).toBe('');
  });

  it('ordenação pelo menu', async () => {
    const seen: (string | null)[] = [];
    libraryReturns((url) => seen.push(url.searchParams.get('sort')));
    renderApp('/sessions', { desktop: true });
    await screen.findByRole('table');
    await userEvent.click(screen.getByRole('button', { name: 'Ordenar' }));
    await userEvent.click(screen.getByRole('menuitemradio', { name: 'Artista' }));
    await waitFor(() => {
      expect(seen.at(-1)).toBe('artist');
    });
  });

  it('editar artista e título pelo menu ⋯', async () => {
    libraryReturns();
    let patch: SessionPatch | undefined;
    server.use(
      http.patch('*/api/sessions/:id', async ({ request }) => {
        patch = (await request.json()) as SessionPatch;
        return HttpResponse.json({ ...ready, ...patch });
      }),
    );
    renderApp('/sessions', { desktop: true });
    const table = await screen.findByRole('table');
    const row = withText(within(table).getAllByRole('row'), 'ST-042');
    await userEvent.click(within(row).getByRole('button', { name: 'Mais ações' }));
    await userEvent.click(screen.getByRole('menuitem', { name: 'Editar artista e título' }));
    const dialog = screen.getByRole('dialog', { name: 'Editar artista e título' });
    const title = within(dialog).getByLabelText('Título');
    await userEvent.clear(title);
    await userEvent.type(title, 'Do It (Remix)');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Salvar' }));
    expect(await screen.findByText('Artista e título atualizados')).toBeInTheDocument();
    expect(patch).toEqual({ artist: 'Nelly Furtado', title: 'Do It (Remix)' });
  });

  it('celular: ⋯ abre o sheet de ações; excluir em processamento mostra o 409', async () => {
    libraryReturns();
    server.use(
      http.delete('*/api/sessions/:id', () =>
        apiError(409, 'session_busy', 'Cancele o processamento antes de excluir.'),
      ),
    );
    const { router } = renderApp('/sessions');
    await userEvent.click(await screen.findByRole('button', { name: 'Mais ações: Basket Case' }));
    const sheet = screen.getByRole('dialog', { name: 'Basket Case' });
    // Em processamento não dá para reprocessar.
    expect(within(sheet).queryByRole('button', { name: 'Reprocessar' })).not.toBeInTheDocument();
    await userEvent.click(within(sheet).getByRole('button', { name: 'Excluir…' }));
    const dialog = screen.getByRole('dialog', { name: 'Excluir “Basket Case”?' });
    expect(dialog).toHaveTextContent('ST-043');
    expect(router.state.location.search).toBe(`?act=delete%3A${separating.id}`);
    await userEvent.click(within(dialog).getByRole('button', { name: 'Excluir' }));
    expect(
      await screen.findByText('Cancele o processamento antes de excluir.'),
    ).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });
  });

  it('excluir com sucesso some com a sessão', async () => {
    let deleted = false;
    server.use(
      http.get('*/api/sessions', () => HttpResponse.json(sessionList(deleted ? [] : [ready]))),
      http.delete('*/api/sessions/:id', () => {
        deleted = true;
        return new HttpResponse(null, { status: 204 });
      }),
    );
    renderApp('/sessions');
    await userEvent.click(await screen.findByRole('button', { name: 'Mais ações: Do It' }));
    await userEvent.click(screen.getByRole('button', { name: 'Excluir…' }));
    await userEvent.click(screen.getByRole('button', { name: 'Excluir' }));
    expect(await screen.findByText('ST-042 excluída')).toBeInTheDocument();
    expect(await screen.findByText('Nenhuma sessão ainda')).toBeInTheDocument();
  });

  it('vazia convida a descobrir', async () => {
    renderApp('/sessions');
    expect(await screen.findByText('Nenhuma sessão ainda')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Descobrir música' })).toHaveAttribute('href', '/');
  });

  it('erro ao carregar → Tentar de novo', async () => {
    let calls = 0;
    server.use(
      http.get('*/api/sessions', () => {
        calls += 1;
        return calls === 1
          ? apiError(500, 'internal_error', 'Erro interno.')
          : HttpResponse.json(sessionList([ready]));
      }),
    );
    renderApp('/sessions');
    expect(await screen.findByText('Erro interno.')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Tentar de novo' }));
    expect(await screen.findByText('Do It')).toBeInTheDocument();
  });

  it('carrega a próxima página com "Carregar mais"', async () => {
    const page1 = Array.from({ length: 30 }, (_, i) =>
      makeSession({ code: `ST-${String(100 + i)}`, title: `Música ${String(i)}` }),
    );
    const last = makeSession({ code: 'ST-999', title: 'A última' });
    server.use(
      http.get('*/api/sessions', ({ request }) => {
        const offset = Number(new URL(request.url).searchParams.get('offset'));
        const list = sessionList([...page1, last]);
        return HttpResponse.json({ ...list, items: offset === 0 ? page1 : [last] });
      }),
    );
    renderApp('/sessions');
    await userEvent.click(await screen.findByRole('button', { name: 'Carregar mais' }));
    expect(await screen.findByText('A última')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Carregar mais' })).not.toBeInTheDocument();
  });
});
