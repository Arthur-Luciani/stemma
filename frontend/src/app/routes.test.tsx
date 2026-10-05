import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';

import { makeSession } from '../test/fixtures';
import { renderApp } from '../test/render';
import { apiError, server } from '../test/server';
import { FakeWebSocket } from '../test/websocket';

describe('rotas e layout', () => {
  it('celular: Descobrir com bottom nav; Mixer sem sessão aberta leva à Biblioteca', async () => {
    renderApp('/');
    expect(
      await screen.findByRole('heading', { name: 'O que vamos separar hoje?' }),
    ).toBeInTheDocument();
    const nav = screen.getByRole('navigation', { name: 'Navegação principal' });
    expect(within(nav).getByRole('link', { name: 'Descobrir' })).toHaveAttribute(
      'aria-current',
      'page',
    );
    expect(within(nav).getByRole('link', { name: 'Mixer' })).toHaveAttribute('href', '/sessions');
    expect(screen.queryByRole('banner')).not.toBeInTheDocument();
  });

  it('desktop: topbar; o Mixer aponta para a última sessão aberta', async () => {
    const session = makeSession({ title: 'Do It', code: 'ST-042' });
    server.use(http.get('*/api/sessions/:id', () => HttpResponse.json(session)));
    renderApp(`/sessions/${session.id}`, { desktop: true });
    expect(await screen.findByRole('heading', { name: 'Do It' })).toBeInTheDocument();
    expect(screen.getByRole('banner')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Mixer' })).toHaveAttribute(
      'href',
      `/sessions/${session.id}/mix`,
    );
  });

  it('abre o /ws uma vez', async () => {
    renderApp('/');
    await screen.findByRole('heading', { name: 'O que vamos separar hoje?' });
    expect(FakeWebSocket.instances.filter((s) => !s.closed)).toHaveLength(1);
    expect(FakeWebSocket.latest().url).toMatch(/\/ws$/);
  });

  it('rota inexistente mostra 404 com volta para Descobrir', async () => {
    renderApp('/nada/aqui');
    expect(await screen.findByText('Página não encontrada')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('link', { name: 'Ir para Descobrir' }));
    expect(
      await screen.findByRole('heading', { name: 'O que vamos separar hoje?' }),
    ).toBeInTheDocument();
  });

  it('sessão que não existe mostra 404', async () => {
    server.use(
      http.get('*/api/sessions/:id', () => apiError(404, 'session_not_found', 'Não existe.')),
    );
    renderApp('/sessions/00000000-0000-4000-8000-000000000999/mix');
    expect(await screen.findByText('Página não encontrada')).toBeInTheDocument();
  });

  it('mixer ainda é placeholder com o cabeçalho da sessão', async () => {
    const session = makeSession({ title: 'Do It', code: 'ST-042' });
    server.use(http.get('*/api/sessions/:id', () => HttpResponse.json(session)));
    renderApp(`/sessions/${session.id}/mix`);
    expect(await screen.findByRole('heading', { name: 'Do It' })).toBeInTheDocument();
    expect(screen.getByText('O mixer chega em breve.')).toBeInTheDocument();
  });
});
