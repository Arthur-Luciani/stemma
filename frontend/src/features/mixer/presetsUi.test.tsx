import { QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';

import type { MixPreset, PresetCreate, PresetUpdate } from '../../api/types';
import { makeDefaultPresets, makePreset } from '../../test/fixtures';
import { testQueryClient } from '../../test/render';
import { apiError, server } from '../../test/server';
import { ToastProvider } from '../../ui/Toast';
import { PresetManager } from './PresetManager';
import { applyPreset, type MixerState } from './mixState';
import { SavePresetDialog } from './SavePresetDialog';

const STEMS = applyPreset(makePreset('x', 0));

function wrap(ui: React.ReactNode) {
  const client = testQueryClient();
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <ToastProvider>{ui}</ToastProvider>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('SavePresetDialog', () => {
  const presets = makeDefaultPresets();

  it('salva o mix atual com o nome e fecha', async () => {
    const posts: PresetCreate[] = [];
    server.use(
      http.post('*/api/presets', async ({ request }) => {
        const body = (await request.json()) as PresetCreate;
        posts.push(body);
        return HttpResponse.json(makePreset(body.name, 5), { status: 201 });
      }),
    );
    const onClose = vi.fn();
    wrap(
      <SavePresetDialog
        mode="create"
        presets={presets}
        stems={{
          ...STEMS,
          drums: { volume: 25, pan: 0, mute: false },
        }}
        onClose={onClose}
      />,
    );
    const save = screen.getByRole('button', { name: 'Salvar' });
    expect(save).toBeDisabled();
    await userEvent.type(screen.getByLabelText('Nome do preset'), ' Bateria baixa ');
    await userEvent.click(save);
    await waitFor(() => {
      expect(onClose).toHaveBeenCalled();
    });
    expect(posts[0]?.name).toBe('Bateria baixa');
    expect(posts[0]?.visible).toBe(true);
    expect(posts[0]?.stems.drums?.volume).toBe(25);
  });

  it('nome repetido (sem diferenciar caixa) bloqueia e oferece atualizar o existente', async () => {
    const patches: PresetUpdate[] = [];
    server.use(
      http.patch('*/api/presets/:id', async ({ request }) => {
        patches.push((await request.json()) as PresetUpdate);
        return HttpResponse.json(presets[1]);
      }),
    );
    const onClose = vi.fn();
    wrap(<SavePresetDialog mode="create" presets={presets} stems={STEMS} onClose={onClose} />);
    await userEvent.type(screen.getByLabelText('Nome do preset'), 'sem VOZ');
    expect(screen.getByRole('alert')).toHaveTextContent('Já existe um preset com esse nome.');
    expect(screen.getByRole('button', { name: 'Salvar' })).toBeDisabled();
    await userEvent.click(screen.getByRole('button', { name: 'Atualizar Sem voz com este mix' }));
    await waitFor(() => {
      expect(onClose).toHaveBeenCalled();
    });
    expect(patches[0]?.stems).toBeDefined();
  });

  it('nome com mais de 40 caracteres mostra o erro e bloqueia', async () => {
    wrap(<SavePresetDialog mode="create" presets={presets} stems={STEMS} onClose={vi.fn()} />);
    await userEvent.click(screen.getByLabelText('Nome do preset'));
    await userEvent.paste('x'.repeat(41));
    expect(screen.getByRole('alert')).toHaveTextContent('passa de 40 caracteres');
    expect(screen.getByRole('button', { name: 'Salvar' })).toBeDisabled();
  });

  it('mantém o diálogo aberto com o erro do servidor', async () => {
    server.use(
      http.post('*/api/presets', () => apiError(409, 'preset_name_taken', 'Já existe um preset.')),
    );
    const onClose = vi.fn();
    wrap(<SavePresetDialog mode="create" presets={[]} stems={STEMS} onClose={onClose} />);
    await userEvent.type(screen.getByLabelText('Nome do preset'), 'Novo');
    await userEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(await screen.findByText('Já existe um preset.')).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();
    expect(screen.getByLabelText('Nome do preset')).toHaveValue('Novo');
  });

  it('renomear permite o próprio nome e não mostra o interruptor', () => {
    wrap(
      <SavePresetDialog
        mode="rename"
        preset={presets[0] as MixPreset}
        presets={presets}
        onClose={vi.fn()}
      />,
    );
    expect(screen.queryByRole('switch')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Salvar' })).toBeEnabled();
  });
});

describe('PresetManager', () => {
  const state: MixerState = { stems: STEMS, loop: null };
  const mixer = (preset: MixPreset | null, dispatch = vi.fn()) => ({
    state,
    preset,
    dispatch,
  });

  it('lista, aplica, mostra/esconde e exclui com confirmação', async () => {
    let list = makeDefaultPresets();
    const patches: { id: string; body: PresetUpdate }[] = [];
    const deleted: string[] = [];
    server.use(
      http.get('*/api/presets', () => HttpResponse.json({ items: list })),
      http.patch('*/api/presets/:id', async ({ request, params }) => {
        const body = (await request.json()) as PresetUpdate;
        patches.push({ id: String(params.id), body });
        return HttpResponse.json(list[0]);
      }),
      http.delete('*/api/presets/:id', ({ params }) => {
        deleted.push(String(params.id));
        list = list.filter((p) => p.id !== params.id);
        return new HttpResponse(null, { status: 204 });
      }),
    );
    const dispatch = vi.fn();
    wrap(
      <PresetManager
        mixer={mixer(list[0] ?? null, dispatch)}
        onClose={vi.fn()}
        onSaveCurrent={vi.fn()}
      />,
    );

    await screen.findByText('Sem voz');
    expect(screen.getByText('Ativo')).toBeInTheDocument();
    expect(screen.getByText('Aplicado')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Aplicar Sem voz' }));
    expect(dispatch).toHaveBeenCalledWith({ type: 'preset', preset: list[1] });

    await userEvent.click(screen.getByRole('switch', { name: 'Mostrar no seletor: Sem voz' }));
    await waitFor(() => {
      expect(patches).toHaveLength(1);
    });
    expect(patches[0]?.body).toEqual({ visible: false });

    await userEvent.click(screen.getByRole('button', { name: 'Mais ações: Sem voz' }));
    await userEvent.click(screen.getByRole('menuitem', { name: 'Excluir' }));
    const dialog = screen.getByRole('dialog', { name: /Excluir “Sem voz”\?/ });
    expect(dialog).toHaveTextContent('O mix das músicas não muda');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Excluir' }));
    await waitFor(() => {
      expect(deleted).toHaveLength(1);
    });
    await waitFor(() => {
      expect(screen.queryByText('Sem voz')).not.toBeInTheDocument();
    });
  });

  it('atualizar com o mix atual pede confirmação e manda os níveis da tela', async () => {
    const list = makeDefaultPresets();
    const patches: PresetUpdate[] = [];
    server.use(
      http.get('*/api/presets', () => HttpResponse.json({ items: list })),
      http.patch('*/api/presets/:id', async ({ request }) => {
        patches.push((await request.json()) as PresetUpdate);
        return HttpResponse.json(list[0]);
      }),
    );
    wrap(<PresetManager mixer={mixer(null)} onClose={vi.fn()} onSaveCurrent={vi.fn()} />);
    await screen.findByText('Sem voz');
    await userEvent.click(screen.getByRole('button', { name: 'Mais ações: Sem voz' }));
    await userEvent.click(screen.getByRole('menuitem', { name: 'Atualizar com o mix atual' }));
    const dialog = screen.getByRole('dialog', { name: /Atualizar “Sem voz”\?/ });
    await userEvent.click(within(dialog).getByRole('button', { name: 'Atualizar' }));
    await waitFor(() => {
      expect(patches).toHaveLength(1);
    });
    expect(patches[0]?.stems?.vocals).toEqual({ volume: 100, pan: 0, mute: false });
  });

  it('reordena com Subir/Descer mandando a lista completa de ids', async () => {
    const list = makeDefaultPresets();
    const orders: string[][] = [];
    server.use(
      http.get('*/api/presets', () => HttpResponse.json({ items: list })),
      http.put('*/api/presets/order', async ({ request }) => {
        const body = (await request.json()) as { ids: string[] };
        orders.push(body.ids);
        return HttpResponse.json({ items: list });
      }),
    );
    wrap(<PresetManager mixer={mixer(null)} onClose={vi.fn()} onSaveCurrent={vi.fn()} />);
    await screen.findByText('Sem voz');
    await userEvent.click(screen.getByRole('button', { name: 'Mais ações: Sem voz' }));
    await userEvent.click(screen.getByRole('menuitem', { name: 'Subir' }));
    await waitFor(() => {
      expect(orders).toHaveLength(1);
    });
    expect(orders[0]?.slice(0, 2)).toEqual([list[1]?.id, list[0]?.id]);
    expect(orders[0]).toHaveLength(5);
  });

  it('lista vazia chama para salvar o mix atual; erro de rede oferece tentar de novo', async () => {
    server.use(http.get('*/api/presets', () => HttpResponse.json({ items: [] })));
    const onSaveCurrent = vi.fn();
    const first = wrap(
      <PresetManager mixer={mixer(null)} onClose={vi.fn()} onSaveCurrent={onSaveCurrent} />,
    );
    expect(await screen.findByText('Nenhum preset ainda')).toBeInTheDocument();
    const buttons = screen.getAllByRole('button', { name: /Salvar/ });
    await userEvent.click(buttons[buttons.length - 1] as HTMLElement);
    expect(onSaveCurrent).toHaveBeenCalled();
    first.unmount();

    server.use(http.get('*/api/presets', () => apiError(500, 'internal', 'Falhou.')));
    wrap(<PresetManager mixer={mixer(null)} onClose={vi.fn()} onSaveCurrent={vi.fn()} />);
    expect(await screen.findByText('Não deu para carregar os presets.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Tentar de novo' })).toBeInTheDocument();
  });
});
