import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';

import type { Job, YtDlpStatus } from '../../api/types';
import { makeJob, makeUpdateRun, makeYtDlpStatus } from '../../test/fixtures';
import { renderApp } from '../../test/render';
import { apiError, server } from '../../test/server';
import { RECENT_MS } from '../update/status';
import { suggestsYtDlpUpdate, ytdlpView } from './status';

const newer = (overrides: Partial<YtDlpStatus> = {}) =>
  makeYtDlpStatus({ latest_version: '2025.10.22', available: true, ...overrides });

function serveYtDlp(data: YtDlpStatus) {
  server.use(http.get('*/api/system/ytdlp', () => HttpResponse.json(data)));
}

function failedJob(code: string, message: string): Job {
  return makeJob(
    {
      state: 'failed',
      stage: 'downloading',
      eta_s: null,
      error_code: code,
      error_message: message,
    },
    { title: 'Everlong', artist: 'Foo Fighters', state: 'failed', code: 'ST-045' },
  );
}

const outdated = failedJob(
  'ytdlp_outdated',
  'O yt-dlp não conseguiu ler o YouTube. Costuma ser o yt-dlp desatualizado.',
);

async function openJobs(...items: Job[]) {
  server.use(http.get('*/api/jobs', () => HttpResponse.json({ items })));
  renderApp('/?jobs=1');
  return screen.findByRole('dialog', { name: 'Processamento' });
}

describe('yt-dlp no card do job que falhou', () => {
  it('erro de yt-dlp velho com versão nova: sugere e atualiza', async () => {
    serveYtDlp(newer());
    let posted = 0;
    server.use(
      http.post('*/api/system/ytdlp', () => {
        posted += 1;
        return HttpResponse.json(
          makeUpdateRun({ from_version: '2025.07.06', target_version: '2025.10.22' }),
          { status: 202 },
        );
      }),
    );
    const sheet = await openJobs(outdated);

    expect(
      await within(sheet).findByText('Já saiu o yt-dlp 2025.10.22. Atualizar costuma resolver.'),
    ).toBeInTheDocument();
    await userEvent.click(within(sheet).getByRole('button', { name: 'Atualizar yt-dlp' }));

    expect(
      await within(sheet).findByText(/Atualizando o yt-dlp para 2025.10.22/),
    ).toBeInTheDocument();
    expect(posted).toBe(1);
    // Atualizar não reprocessa: o "Tentar de novo" continua lá.
    expect(within(sheet).getByRole('button', { name: 'Tentar de novo' })).toBeInTheDocument();
  });

  it('yt-dlp já em dia: não sugere nada', async () => {
    const sheet = await openJobs(outdated);
    await within(sheet).findByText(/não conseguiu ler o YouTube/);
    expect(
      within(sheet).queryByRole('button', { name: 'Atualizar yt-dlp' }),
    ).not.toBeInTheDocument();
  });

  it('outro erro (cookies): não sugere atualizar', async () => {
    serveYtDlp(newer());
    const sheet = await openJobs(
      failedJob('youtube_login_required', 'YouTube pediu login. Atualize os cookies.'),
    );
    await within(sheet).findByText('YouTube pediu login. Atualize os cookies.');
    expect(
      within(sheet).queryByRole('button', { name: 'Atualizar yt-dlp' }),
    ).not.toBeInTheDocument();
  });

  it('com job ativo: botão desabilitado e explica por quê', async () => {
    serveYtDlp(newer({ active_jobs: 1 }));
    const sheet = await openJobs(outdated);
    const button = await within(sheet).findByRole('button', { name: 'Atualizar yt-dlp' });
    expect(button).toBeDisabled();
    expect(
      within(sheet).getByText('Espere o processamento terminar para atualizar.'),
    ).toBeInTheDocument();
  });

  it('a última tentativa falhou: mostra o motivo no lugar da sugestão', async () => {
    serveYtDlp(
      newer({
        last_run: makeUpdateRun({
          state: 'failed',
          target_version: '2025.10.22',
          message:
            'A atualização do yt-dlp para 2025.10.22 falhou. O yt-dlp 2025.07.06 continua no ar.',
          finished_at: new Date().toISOString(),
        }),
      }),
    );
    const sheet = await openJobs(outdated);
    expect(await within(sheet).findByText(/continua no ar/)).toBeInTheDocument();
    expect(within(sheet).getByRole('button', { name: 'Atualizar yt-dlp' })).toBeEnabled();
  });

  it('acabou de atualizar: avisa e manda tentar de novo', async () => {
    serveYtDlp(
      makeYtDlpStatus({
        installed_version: '2025.10.22',
        latest_version: '2025.10.22',
        last_run: makeUpdateRun({
          state: 'succeeded',
          target_version: '2025.10.22',
          finished_at: new Date().toISOString(),
        }),
      }),
    );
    const sheet = await openJobs(outdated);
    expect(
      await within(sheet).findByText('yt-dlp atualizado para 2025.10.22. Tente de novo.'),
    ).toBeInTheDocument();
  });

  it('instalação sem a tarefa: não oferece', async () => {
    serveYtDlp(newer({ can_update: false }));
    const sheet = await openJobs(outdated);
    await within(sheet).findByText(/não conseguiu ler o YouTube/);
    expect(
      within(sheet).queryByRole('button', { name: 'Atualizar yt-dlp' }),
    ).not.toBeInTheDocument();
  });
});

describe('yt-dlp no erro da busca', () => {
  it('mostra a mensagem do servidor e a sugestão junto do Tentar de novo', async () => {
    serveYtDlp(newer());
    server.use(
      http.get('*/api/search', () =>
        apiError(
          502,
          'ytdlp_outdated',
          'O yt-dlp não conseguiu ler o YouTube. Costuma ser o yt-dlp desatualizado.',
        ),
      ),
    );
    renderApp('/?q=basket');

    const alert = await screen.findByRole('alert');
    expect(within(alert).getByText(/não conseguiu ler o YouTube/)).toBeInTheDocument();
    expect(
      await within(alert).findByRole('button', { name: 'Atualizar yt-dlp' }),
    ).toBeInTheDocument();
    expect(within(alert).getByRole('button', { name: 'Tentar de novo' })).toBeInTheDocument();
  });
});

describe('aviso de yt-dlp atrasado', () => {
  it('em dia ou só com versão nova recente: nada fixo no app', async () => {
    serveYtDlp(newer());
    renderApp('/sessions');
    await screen.findByRole('heading', { name: 'Biblioteca' });
    expect(screen.queryByText('yt-dlp desatualizado')).not.toBeInTheDocument();
  });

  it('celular: atrasado há dias mostra a faixa, que atualiza', async () => {
    serveYtDlp(newer({ stale: true }));
    let posted = 0;
    server.use(
      http.post('*/api/system/ytdlp', () => {
        posted += 1;
        return HttpResponse.json(makeUpdateRun({ target_version: '2025.10.22' }), {
          status: 202,
        });
      }),
    );
    renderApp('/sessions');

    const text = await screen.findByText('yt-dlp desatualizado');
    const banner = text.closest('[role="status"]') as HTMLElement;
    await userEvent.click(within(banner).getByRole('button', { name: 'Atualizar' }));

    expect(await screen.findByText('Atualizando o yt-dlp…')).toBeInTheDocument();
    expect(posted).toBe(1);
  });

  it('desktop: chip na topbar', async () => {
    serveYtDlp(newer({ stale: true }));
    renderApp('/sessions', { desktop: true });
    expect(await screen.findByRole('button', { name: 'Atualizar yt-dlp' })).toBeInTheDocument();
  });
});

describe('ytdlpView', () => {
  it('sucesso antigo some; com versão nova, a nova ganha', () => {
    const old = new Date(Date.now() - RECENT_MS - 1000).toISOString();
    const done = makeUpdateRun({ state: 'succeeded', finished_at: old });
    expect(ytdlpView(makeYtDlpStatus({ last_run: done })).kind).toBe('upToDate');
    expect(ytdlpView(newer({ last_run: done })).kind).toBe('available');
    expect(ytdlpView(makeYtDlpStatus({ check: 'unavailable' })).kind).toBe('unknown');
  });

  it('só os erros típicos de yt-dlp velho sugerem atualizar', () => {
    expect(suggestsYtDlpUpdate('ytdlp_outdated')).toBe(true);
    expect(suggestsYtDlpUpdate('youtube_format_unavailable')).toBe(true);
    expect(suggestsYtDlpUpdate('video_unavailable')).toBe(false);
    expect(suggestsYtDlpUpdate(null)).toBe(false);
  });
});

it('a versão do yt-dlp aparece no sheet de atualização do Stemma', async () => {
  server.use(
    http.get('*/api/system/update', () =>
      HttpResponse.json({
        current_version: '1.5.0',
        check: 'ok',
        checked_at: null,
        latest_version: '1.5.1',
        available: true,
        notes: [],
        can_update: true,
        active_jobs: 0,
        last_run: null,
      }),
    ),
  );
  renderApp('/sessions?atualizacao=1');
  const sheet = await screen.findByRole('dialog', { name: 'Sobre o Stemma' });
  await waitFor(() => {
    expect(within(sheet).getByText('yt-dlp 2025.07.06')).toBeInTheDocument();
  });
});
