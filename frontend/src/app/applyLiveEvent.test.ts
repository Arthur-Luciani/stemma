import type { Job, SessionList } from '../api/types';
import { makeJob, makeSession, sessionList } from '../test/fixtures';
import { testQueryClient } from '../test/render';
import { createLiveEventHandler } from './applyLiveEvent';
import { queryKeys } from './queryKeys';

function setup() {
  const client = testQueryClient();
  const handler = createLiveEventHandler(client, { listDebounceMs: 100 });
  return { client, handler };
}

describe('applyLiveEvent', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('session.updated atualiza o detalhe, a sessão dentro do job e invalida listas (com debounce)', () => {
    const { client, handler } = setup();
    const job = makeJob();
    client.setQueryData(queryKeys.jobs, [job]);
    const listKey = queryKeys.sessionList({ sort: 'newest' });
    client.setQueryData<SessionList>(listKey, sessionList([job.session]));

    const updated = { ...job.session, progress: 80 };
    handler.handle({ type: 'session.updated', data: { session: updated } });
    handler.handle({ type: 'session.updated', data: { session: { ...updated, progress: 81 } } });

    expect(client.getQueryData(queryKeys.session(job.session_id))).toMatchObject({ progress: 81 });
    expect(client.getQueryData<Job[]>(queryKeys.jobs)?.[0]?.session.progress).toBe(81);
    expect(client.getQueryState(listKey)?.isInvalidated).toBe(false);
    vi.advanceTimersByTime(100);
    expect(client.getQueryState(listKey)?.isInvalidated).toBe(true);
    handler.dispose();
  });

  it('job.updated insere, atualiza e tira jobs descartados/cancelados', () => {
    const { client, handler } = setup();
    client.setQueryData<Job[]>(queryKeys.jobs, []);
    const job = makeJob({ state: 'queued', position: 1 });

    handler.handle({ type: 'job.updated', data: { job } });
    expect(client.getQueryData<Job[]>(queryKeys.jobs)).toHaveLength(1);

    handler.handle({ type: 'job.updated', data: { job: { ...job, state: 'running' } } });
    expect(client.getQueryData<Job[]>(queryKeys.jobs)?.[0]?.state).toBe('running');

    handler.handle({ type: 'job.updated', data: { job: { ...job, state: 'cancelled' } } });
    expect(client.getQueryData<Job[]>(queryKeys.jobs)).toHaveLength(0);

    const done = { ...job, state: 'done' as const, dismissed_at: new Date().toISOString() };
    handler.handle({ type: 'job.updated', data: { job: done } });
    expect(client.getQueryData<Job[]>(queryKeys.jobs)).toHaveLength(0);
    handler.dispose();
  });

  it('job de export encerrado não entra no dock', () => {
    const { client, handler } = setup();
    client.setQueryData<Job[]>(queryKeys.jobs, []);
    handler.handle({
      type: 'job.updated',
      data: { job: makeJob({ kind: 'export', state: 'done' }) },
    });
    expect(client.getQueryData<Job[]>(queryKeys.jobs)).toHaveLength(0);
    handler.dispose();
  });

  it('session.deleted remove o detalhe e os jobs da sessão', () => {
    const { client, handler } = setup();
    const session = makeSession();
    const job = makeJob({ state: 'failed' }, { id: session.id });
    client.setQueryData(queryKeys.session(session.id), session);
    client.setQueryData(queryKeys.jobs, [job]);

    handler.handle({ type: 'session.deleted', data: { id: session.id } });
    expect(client.getQueryData(queryKeys.session(session.id))).toBeUndefined();
    expect(client.getQueryData<Job[]>(queryKeys.jobs)).toEqual([]);
    handler.dispose();
  });

  it('resync invalida tudo (eventos perdidos na queda)', () => {
    const { client, handler } = setup();
    client.setQueryData(queryKeys.jobs, []);
    handler.resync();
    expect(client.getQueryState(queryKeys.jobs)?.isInvalidated).toBe(true);
  });
});
