import { act, fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';

import type { Export, MixState, MixStateIn } from '../../api/types';
import { stubAudioGlobals } from '../../test/audio';
import { makeExport, makeMix, makeSession } from '../../test/fixtures';
import { renderApp } from '../../test/render';
import { apiError, server } from '../../test/server';
import { FakeWebSocket } from '../../test/websocket';

/** Backend falso com o mix e os exports guardados entre renders (recarregar a página). */
function fakeBackend(sessionOverrides = {}) {
  const session = makeSession({
    title: 'Do It',
    artist: 'Nelly Furtado',
    code: 'ST-042',
    duration_s: 221,
    metrics: { lufs: -10.6, true_peak_db: 0.9 },
    ...sessionOverrides,
  });
  let mix: MixState = makeMix({ preset: 'no_drums', stems: { ...makeMix().stems } });
  mix.stems.drums = { volume: 100, pan: 0, mute: true, solo: false };
  const puts: MixStateIn[] = [];
  const calls: string[] = [];
  let exports: Export[] = [
    makeExport({
      session_id: session.id,
      format: 'wav',
      preset: 'original',
      file_name: 'Nelly Furtado - Do It (Original).wav',
      created_at: '2026-09-09T10:00:00Z',
    }),
  ];
  server.use(
    http.get('*/api/sessions/:id', () => HttpResponse.json(session)),
    http.get('*/api/sessions/:id/mix', () => HttpResponse.json(mix)),
    http.put('*/api/sessions/:id/mix', async ({ request }) => {
      const body = (await request.json()) as MixStateIn;
      puts.push(body);
      calls.push('put');
      mix = { ...mix, ...body, updated_at: new Date().toISOString() };
      return HttpResponse.json(mix);
    }),
    http.get('*/api/sessions/:id/peaks/*', () =>
      HttpResponse.json({ duration_s: 221, peaks: [0.2, 0.8, 0.5, 0.3] }),
    ),
    http.get('*/api/sessions/:id/exports', () => HttpResponse.json({ items: exports })),
    http.post('*/api/sessions/:id/exports', async ({ request }) => {
      const body = (await request.json()) as { format: 'wav' | 'mp3' };
      calls.push(`post:${body.format}`);
      const created = makeExport({
        session_id: session.id,
        format: body.format,
        preset: mix.preset,
        state: 'queued',
        progress: 0,
        size_bytes: null,
        lufs: null,
        file_name: `Nelly Furtado - Do It.${body.format}`,
      });
      exports = [created, ...exports];
      return HttpResponse.json(created, { status: 201 });
    }),
  );
  return { session, puts, calls, getExports: () => exports };
}

describe('Mixer', () => {
  let audio: ReturnType<typeof stubAudioGlobals>;

  beforeEach(() => {
    audio = stubAudioGlobals();
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  async function openDesktop(path: string) {
    const result = renderApp(path, { desktop: true });
    await screen.findByRole('heading', { name: 'Do It' });
    await waitFor(() => {
      expect(audio.media).toHaveLength(4);
    });
    act(() => {
      audio.load(221);
    });
    await screen.findByRole('radiogroup', { name: 'Presets' });
    return result;
  }

  it('desktop: restaura o mix salvo, mixa, vira Personalizado e salva', async () => {
    const { session, puts } = fakeBackend();
    await openDesktop(`/sessions/${session.id}/mix`);

    expect(screen.getByRole('radio', { name: 'Sem bateria' })).toHaveAttribute(
      'aria-checked',
      'true',
    );
    const drums = screen.getByRole('region', { name: 'Bateria' });
    expect(within(drums).getByRole('button', { name: 'Silenciar Bateria' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(screen.getByText('−10.6')).toBeInTheDocument();
    expect(screen.getByText('ST-042 · 3:41 · hoje', { exact: false })).toBeInTheDocument();

    const vocals = screen.getByRole('region', { name: 'Voz' });
    await userEvent.click(within(vocals).getByRole('button', { name: 'Solo de Voz' }));
    expect(screen.getByText('Personalizado')).toBeInTheDocument();
    expect(
      screen.getAllByRole('radio').every((r) => r.getAttribute('aria-checked') === 'false'),
    ).toBe(true);
    await waitFor(() => {
      expect(puts).toHaveLength(1);
    });
    expect(puts[0]?.preset).toBe('custom');
    expect(puts[0]?.stems.vocals?.solo).toBe(true);

    await userEvent.click(screen.getByRole('radio', { name: 'Original' }));
    expect(within(drums).getByRole('button', { name: 'Silenciar Bateria' })).toHaveAttribute(
      'aria-pressed',
      'false',
    );
    await waitFor(() => {
      expect(puts.at(-1)?.preset).toBe('original');
    });
  });

  it('desktop: atalhos tocam, mutam, solam e marcam o loop A–B', async () => {
    const { session, puts } = fakeBackend();
    await openDesktop(`/sessions/${session.id}/mix`);

    await userEvent.keyboard(' ');
    expect(audio.media.every((el) => !el.paused)).toBe(true);
    expect(screen.getByRole('button', { name: 'Pausar' })).toBeInTheDocument();

    await userEvent.keyboard('1');
    expect(screen.getByRole('button', { name: 'Silenciar Voz' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    await userEvent.keyboard('{Shift>}2{/Shift}');
    expect(screen.getByRole('button', { name: 'Solo de Bateria' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );

    // A no início e B depois de avançar 10 s (→ → é ±5 s).
    await userEvent.keyboard('a');
    expect(screen.getByText('A em 0:00 · marque o B')).toBeInTheDocument();
    await userEvent.keyboard('{ArrowRight}{ArrowRight}');
    for (const el of audio.media) el.currentTime = 10;
    await userEvent.keyboard('b');
    expect(screen.getByText('0:00 → 0:10')).toBeInTheDocument();
    await waitFor(() => {
      expect(puts.at(-1)?.loop_b_s).toBeCloseTo(10, 0);
    });

    // Setas num slider mexem nele, não no tempo.
    const fader = screen.getByRole('slider', { name: 'Volume de Baixo' });
    fader.focus();
    await userEvent.keyboard('{ArrowLeft}');
    expect(fader).toHaveAttribute('aria-valuenow', '99');
  });

  it('recarregar a página traz o mix salvo (com o loop)', async () => {
    const { session } = fakeBackend();
    const first = await openDesktop(`/sessions/${session.id}/mix`);
    await userEvent.click(screen.getByRole('radio', { name: 'Só voz' }));
    fireEvent.keyDown(document.body, { code: 'KeyB', key: 'b' });
    // Sair da tela salva o pendente na hora.
    first.unmount();
    await waitFor(() => {
      expect(audio.contexts.every((c) => c.state === 'closed')).toBe(true);
    });

    audio.media.length = 0;
    await openDesktop(`/sessions/${session.id}/mix`);
    await waitFor(() => {
      expect(screen.getByRole('radio', { name: 'Só voz' })).toHaveAttribute('aria-checked', 'true');
    });
  });

  it('desktop: exportar salva o mix antes, mostra o progresso ao vivo e deixa baixar', async () => {
    const { session, calls, getExports } = fakeBackend();
    const { router } = await openDesktop(`/sessions/${session.id}/mix`);

    await userEvent.click(screen.getByRole('button', { name: 'Solo de Baixo' }));
    await userEvent.click(screen.getByRole('button', { name: 'Exportar' }));
    expect(router.state.location.search).toBe('?export=1');
    const popover = screen.getByRole('dialog', { name: 'Exportar mixagem' });
    expect(within(popover).getByText('Original · WAV')).toBeInTheDocument();

    await userEvent.click(within(popover).getByRole('button', { name: 'Exportar MP3 320' }));
    await waitFor(() => {
      expect(calls).toContain('post:mp3');
    });
    // O save pendente (solo) foi antes do pedido de export.
    expect(calls.indexOf('put')).toBeLessThan(calls.indexOf('post:mp3'));
    expect(await within(popover).findByText('Na fila…')).toBeInTheDocument();

    const queued = getExports().find((e) => e.format === 'mp3');
    if (!queued) throw new Error('export não criado');
    const created = { ...queued, state: 'running' as const, progress: 64 };
    act(() => {
      FakeWebSocket.latest().receive({ type: 'export.updated', data: { export: created } });
    });
    expect(await within(popover).findByText('Gerando MP3…')).toBeInTheDocument();
    expect(within(popover).getByText('64%')).toBeInTheDocument();

    act(() => {
      FakeWebSocket.latest().receive({
        type: 'export.updated',
        data: { export: { ...created, state: 'done', progress: 100, size_bytes: 7_100_000 } },
      });
    });
    const link = await within(popover).findByRole('link', {
      name: 'Baixar Nelly Furtado - Do It.mp3',
    });
    expect(link).toHaveAttribute('href', `/api/exports/${created.id}/file`);

    await userEvent.keyboard('{Escape}');
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('desktop: se o save do mix falha, o export não sai com o mix antigo', async () => {
    const { session, calls } = fakeBackend();
    await openDesktop(`/sessions/${session.id}/mix`);
    server.use(http.put('*/api/sessions/:id/mix', () => apiError(503, 'boom', 'Servidor fora.')));

    await userEvent.click(screen.getByRole('button', { name: 'Solo de Baixo' }));
    await userEvent.click(screen.getByRole('button', { name: 'Exportar' }));
    const popover = screen.getByRole('dialog', { name: 'Exportar mixagem' });
    await userEvent.click(within(popover).getByRole('button', { name: 'Exportar MP3 320' }));

    expect(await screen.findByText('Servidor fora.')).toBeInTheDocument();
    expect(calls.some((c) => c.startsWith('post'))).toBe(false);
  });

  it('celular: Modo prática primeiro, "Ajustar" abre as lanes e o back volta', async () => {
    const { session } = fakeBackend();
    const { router } = renderApp(`/sessions/${session.id}/mix`);
    await screen.findByRole('heading', { name: 'Do It' });
    await waitFor(() => {
      expect(audio.media).toHaveLength(4);
    });
    act(() => {
      audio.load(221);
    });

    // 1f: grade de presets com "Personalizado" e play grande, sem faders.
    expect(await screen.findByText('Personalizado')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Tocar' })).toBeInTheDocument();
    expect(screen.queryByRole('slider')).not.toBeInTheDocument();
    expect(
      screen.queryByRole('navigation', { name: 'Navegação principal' }),
    ).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Ajustar' }));
    expect(router.state.location.search).toBe('?view=ajustar');
    expect(screen.getByRole('slider', { name: 'Volume de Voz' })).toBeInTheDocument();

    // Pan fino num sheet com URL própria.
    await userEvent.click(screen.getByRole('button', { name: 'Pan de Baixo: C' }));
    const sheet = screen.getByRole('dialog', { name: 'Pan de Baixo' });
    within(sheet).getByRole('slider', { name: 'Pan de Baixo' }).focus();
    await userEvent.keyboard('{ArrowRight}{ArrowRight}');
    expect(screen.getByRole('button', { name: 'Pan de Baixo: R2' })).toBeInTheDocument();
    act(() => {
      void router.navigate(-1);
    });
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });

    act(() => {
      void router.navigate(-1);
    });
    expect(await screen.findByRole('button', { name: 'Ajustar' })).toBeInTheDocument();
  });

  it('sessão que não está pronta manda para a página da sessão', async () => {
    const { session } = fakeBackend({ state: 'separating' });
    renderApp(`/sessions/${session.id}/mix`, { desktop: true });
    expect(await screen.findByText('Esta sessão ainda não tem stems.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Abrir sessão' })).toHaveAttribute(
      'href',
      `/sessions/${session.id}`,
    );
    expect(audio.media).toHaveLength(0);
  });
});
