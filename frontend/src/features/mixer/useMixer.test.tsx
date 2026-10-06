import { QueryClientProvider } from '@tanstack/react-query';
import { act, renderHook, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import type { ReactNode } from 'react';

import type { MixStateIn } from '../../api/types';
import type { AudioEngine } from '../../audio/AudioEngine';
import { makeMix } from '../../test/fixtures';
import { testQueryClient } from '../../test/render';
import { apiError, server } from '../../test/server';
import { ToastProvider } from '../../ui/Toast';
import { useMixer } from './useMixer';

const SESSION = '00000000-0000-4000-8000-00000000abcd';

function setup({ debounceMs = 40, engine = null as AudioEngine | null } = {}) {
  const puts: MixStateIn[] = [];
  server.use(
    http.get('*/api/sessions/:id/mix', () =>
      HttpResponse.json(makeMix({ preset: 'no_vocals', loop_a_s: 5, loop_b_s: 9 })),
    ),
    http.put('*/api/sessions/:id/mix', async ({ request }) => {
      const body = (await request.json()) as MixStateIn;
      puts.push(body);
      return HttpResponse.json({ ...body, updated_at: new Date().toISOString() });
    }),
  );
  const client = testQueryClient();
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>
      <ToastProvider>{children}</ToastProvider>
    </QueryClientProvider>
  );
  const hook = renderHook(() => useMixer(SESSION, engine, { debounceMs }), { wrapper });
  return { ...hook, puts };
}

describe('useMixer', () => {
  it('carrega o mix salvo e deriva o preset', async () => {
    const { result } = setup();
    await waitFor(() => {
      expect(result.current.state).not.toBeNull();
    });
    expect(result.current.state?.loop).toEqual({ a: 5, b: 9 });
    // O mix salvo é tudo em 100 sem mute: bate com Original, não com o rótulo que veio.
    expect(result.current.preset).toBe('original');
  });

  it('salva uma vez só, com o último estado, depois do debounce', async () => {
    const { result, puts } = setup();
    await waitFor(() => {
      expect(result.current.state).not.toBeNull();
    });
    act(() => {
      result.current.dispatch({ type: 'volume', stem: 'bass', value: 10 });
      result.current.dispatch({ type: 'volume', stem: 'bass', value: 20 });
      result.current.dispatch({ type: 'mute', stem: 'vocals' });
    });
    expect(result.current.preset).toBe('custom');
    expect(puts).toHaveLength(0);
    await waitFor(() => {
      expect(puts).toHaveLength(1);
    });
    expect(puts[0]?.stems.bass?.volume).toBe(20);
    expect(puts[0]?.stems.vocals?.mute).toBe(true);
    expect(puts[0]?.preset).toBe('custom');
    expect(puts[0]?.loop_a_s).toBe(5);
  });

  it('não salva se o mix voltou ao que estava salvo', async () => {
    const { result, puts } = setup();
    await waitFor(() => {
      expect(result.current.state).not.toBeNull();
    });
    act(() => {
      result.current.dispatch({ type: 'volume', stem: 'bass', value: 10 });
      result.current.dispatch({ type: 'volume', stem: 'bass', value: 100 });
    });
    await act(() => result.current.flush());
    expect(puts).toHaveLength(0);
  });

  it('flush salva na hora (antes de exportar) e sair da tela salva o pendente', async () => {
    const { result, puts, unmount } = setup({ debounceMs: 60_000 });
    await waitFor(() => {
      expect(result.current.state).not.toBeNull();
    });
    act(() => {
      result.current.dispatch({ type: 'preset', preset: 'no_drums' });
    });
    await act(() => result.current.flush());
    expect(puts.map((p) => p.preset)).toEqual(['no_drums']);

    act(() => {
      result.current.dispatch({ type: 'loop', loop: null });
    });
    unmount();
    await waitFor(() => {
      expect(puts).toHaveLength(2);
    });
    expect(puts[1]?.loop_a_s).toBeNull();
  });

  it('falha no save tenta de novo no próximo', async () => {
    const { result, puts } = setup({ debounceMs: 60_000 });
    await waitFor(() => {
      expect(result.current.state).not.toBeNull();
    });
    server.use(
      http.put('*/api/sessions/:id/mix', () => apiError(500, 'boom', 'Falhou.'), { once: true }),
    );
    act(() => {
      result.current.dispatch({ type: 'solo', stem: 'drums' });
    });
    let ok: boolean | undefined;
    await act(async () => {
      ok = await result.current.flush();
    });
    expect(ok).toBe(false);
    expect(puts).toHaveLength(0);
    await act(async () => {
      ok = await result.current.flush();
    });
    expect(ok).toBe(true);
    expect(puts).toHaveLength(1);
  });

  it('marca A e depois B; limpar descarta um A pendente', async () => {
    const { result } = setup({ debounceMs: 60_000 });
    await waitFor(() => {
      expect(result.current.state).not.toBeNull();
    });
    act(() => {
      result.current.markA(30);
    });
    expect(result.current.pendingA).toBe(30);
    expect(result.current.state?.loop).toBeNull();
    act(() => {
      result.current.markB(45);
    });
    expect(result.current.state?.loop).toEqual({ a: 30, b: 45 });
    expect(result.current.pendingA).toBeNull();

    act(() => {
      result.current.markA(50);
    });
    expect(result.current.pendingA).toBe(50);
    act(() => {
      result.current.dispatch({ type: 'loop', loop: null });
    });
    expect(result.current.pendingA).toBeNull();
  });

  it('aplica o mix e o loop no AudioEngine', async () => {
    const engine = { setMix: vi.fn(), setLoop: vi.fn() };
    const { result } = setup({ engine: engine as unknown as AudioEngine });
    await waitFor(() => {
      expect(engine.setMix).toHaveBeenCalled();
    });
    expect(engine.setLoop).toHaveBeenLastCalledWith(5, 9);
    act(() => {
      result.current.dispatch({ type: 'mute', stem: 'other' });
    });
    const last = engine.setMix.mock.lastCall?.[0] as Record<string, { mute: boolean }>;
    expect(last.other?.mute).toBe(true);
    expect(engine.setLoop).toHaveBeenCalledTimes(1);
  });
});
