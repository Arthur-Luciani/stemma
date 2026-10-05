import { http, HttpResponse } from 'msw';

import { apiError, server } from '../test/server';
import { ApiError, NETWORK_ERROR } from './client';
import { deleteSession, getSession, listSessions } from './endpoints';

describe('client da API', () => {
  it('devolve os dados quando dá certo', async () => {
    server.use(
      http.get('*/api/sessions', ({ request }) => {
        const url = new URL(request.url);
        // `state` repetível, como o backend espera.
        expect(url.searchParams.getAll('state')).toEqual(['queued', 'separating']);
        return HttpResponse.json({ items: [], total: 0, counts: {} });
      }),
    );
    const data = await listSessions({ state: ['queued', 'separating'] });
    expect(data.total).toBe(0);
  });

  it('normaliza {"error": {code, message}} em ApiError', async () => {
    server.use(
      http.get('*/api/sessions/:id', () =>
        apiError(404, 'session_not_found', 'Sessão não encontrada.'),
      ),
    );
    const error = await getSession('x').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({
      status: 404,
      code: 'session_not_found',
      message: 'Sessão não encontrada.',
    });
  });

  it('corpo de erro fora do padrão vira erro genérico em PT-BR', async () => {
    server.use(http.delete('*/api/sessions/:id', () => new HttpResponse('boom', { status: 500 })));
    await expect(deleteSession('x')).rejects.toMatchObject({
      status: 500,
      code: 'unknown_error',
      message: 'Algo deu errado. Tente de novo.',
    });
  });

  it('falha de rede vira network_error', async () => {
    server.use(http.get('*/api/sessions/:id', () => HttpResponse.error()));
    await expect(getSession('x')).rejects.toMatchObject({
      code: NETWORK_ERROR,
      message: 'Sem conexão com o servidor.',
    });
  });
});
