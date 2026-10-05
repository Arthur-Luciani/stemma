import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';

import { FakeAudioContext, FakeMedia } from '../../test/audio';
import { makeSession, sessionList } from '../../test/fixtures';
import { renderApp } from '../../test/render';
import { server } from '../../test/server';

describe('/dev/engine', () => {
  let media: FakeMedia[];
  let contexts: FakeAudioContext[];

  beforeEach(() => {
    media = [];
    contexts = [];
    vi.stubGlobal(
      'AudioContext',
      class extends FakeAudioContext {
        constructor() {
          super();
          contexts.push(this);
        }
      },
    );
    vi.stubGlobal(
      'Audio',
      class extends FakeMedia {
        constructor() {
          super();
          media.push(this);
        }
      },
    );
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null);
  });

  afterEach(() => {
    // Sem `unstubAllGlobals`: desfaria também o WebSocket falso do setup global. Os falsos de
    // `AudioContext` e `Audio` podem ficar: só o engine os usa.
    vi.restoreAllMocks();
  });

  it('carrega a sessão escolhida, toca, mede e fecha o contexto ao sair', async () => {
    const session = makeSession({ code: 'ST-007', title: 'Let It Be', artist: 'The Beatles' });
    server.use(
      http.get('*/api/sessions', () => HttpResponse.json(sessionList([session]))),
      http.get('*/api/sessions/:id/peaks/*', () =>
        HttpResponse.json({ duration_s: 240, peaks: [0.2, 0.8, 0.5] }),
      ),
    );
    const { router } = renderApp('/dev/engine');

    await userEvent.selectOptions(
      await screen.findByLabelText('Sessão pronta'),
      await screen.findByRole('option', { name: 'ST-007 · The Beatles — Let It Be' }),
    );
    expect(await screen.findByText('Carregando os stems…')).toBeInTheDocument();
    await waitFor(() => {
      expect(media).toHaveLength(4);
    });
    expect(media[0]?.src).toBe(`/api/sessions/${session.id}/stems/vocals.mp3`);
    for (const el of media) el.loaded(240);

    await userEvent.click(await screen.findByRole('button', { name: 'Tocar' }));
    expect(media.every((el) => !el.paused)).toBe(true);
    expect(contexts[0]?.state).toBe('running');
    expect(screen.getByText('tocando')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Silenciar Voz' }));
    expect(screen.getByRole('button', { name: 'Silenciar Voz' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );

    await userEvent.click(screen.getByRole('button', { name: 'Iniciar medição' }));
    await userEvent.click(screen.getByRole('button', { name: 'Parar e gerar relatório' }));
    expect(screen.getByRole('button', { name: 'Copiar relatório' })).toBeInTheDocument();
    expect(screen.getByText(/"thresholdMs": 30/)).toBeInTheDocument();

    await router.navigate('/sessions');
    await waitFor(() => {
      expect(contexts[0]?.state).toBe('closed');
    });
  });
});
