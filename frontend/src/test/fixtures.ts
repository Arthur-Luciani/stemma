import type {
  Export,
  Job,
  MixState,
  SearchResult,
  Session,
  SessionList,
  SessionState,
  SystemUpdate,
  UpdateRun,
} from '../api/types';

let seq = 0;
const uuid = () => {
  seq += 1;
  return `00000000-0000-4000-8000-${String(seq).padStart(12, '0')}`;
};

export function makeSession(overrides: Partial<Session> = {}): Session {
  const id = overrides.id ?? uuid();
  return {
    id,
    code: 'ST-001',
    artist: 'Green Day',
    title: 'Basket Case',
    state: 'ready',
    progress: 0,
    duration_s: 182,
    source_url: 'https://www.youtube.com/watch?v=abc',
    source_title: 'Green Day - Basket Case [Official Music Video]',
    source_channel: 'Green Day',
    thumbnail_url: null,
    stems: [],
    metrics: null,
    error_code: null,
    error_message: null,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    processed_at: null,
    ...overrides,
  };
}

export function makeJob(overrides: Partial<Job> = {}, session?: Partial<Session>): Job {
  const s = makeSession({ state: 'separating', progress: 62, ...session });
  return {
    id: uuid(),
    kind: 'process',
    state: 'running',
    stage: 'separating',
    progress: 62,
    position: null,
    eta_s: 40,
    attempt: 1,
    export_id: null,
    error_code: null,
    error_message: null,
    created_at: new Date().toISOString(),
    started_at: new Date().toISOString(),
    finished_at: null,
    dismissed_at: null,
    session_id: s.id,
    session: s,
    ...overrides,
  };
}

export function makeResult(overrides: Partial<SearchResult> = {}): SearchResult {
  return {
    source_url: 'https://www.youtube.com/watch?v=abc',
    source_title: 'Green Day - Basket Case [Official Music Video]',
    source_channel: 'Green Day',
    duration_s: 182,
    thumbnail_url: null,
    artist: 'Green Day',
    title: 'Basket Case',
    ...overrides,
  };
}

const ZERO: Record<SessionState, number> = {
  draft: 0,
  queued: 0,
  downloading: 0,
  separating: 0,
  ready: 0,
  failed: 0,
};

export function sessionList(
  items: Session[],
  counts: Partial<SessionList['counts']> = {},
): SessionList {
  const all = { ...ZERO };
  for (const s of items) all[s.state] += 1;
  return { items, total: items.length, counts: { ...all, ...counts } };
}

const STEM_DEFAULT = { volume: 100, pan: 0, mute: false, solo: false };

export function makeMix(overrides: Partial<MixState> = {}): MixState {
  return {
    stems: {
      vocals: { ...STEM_DEFAULT },
      drums: { ...STEM_DEFAULT },
      bass: { ...STEM_DEFAULT },
      other: { ...STEM_DEFAULT },
    },
    preset: 'original',
    loop_a_s: null,
    loop_b_s: null,
    updated_at: null,
    ...overrides,
  };
}

export function makeExport(overrides: Partial<Export> = {}): Export {
  return {
    id: uuid(),
    session_id: uuid(),
    format: 'mp3',
    preset: 'original',
    stems: makeMix().stems,
    state: 'done',
    progress: 100,
    size_bytes: 7_100_000,
    lufs: -10.6,
    error_code: null,
    error_message: null,
    file_name: 'Green Day - Basket Case (Original).mp3',
    created_at: new Date().toISOString(),
    finished_at: new Date().toISOString(),
    ...overrides,
  };
}

/** `GET /api/system/update` sem versão nova (o padrão do servidor de teste). */
export function makeSystemUpdate(overrides: Partial<SystemUpdate> = {}): SystemUpdate {
  return {
    current_version: '1.5.0',
    check: 'ok',
    checked_at: '2026-10-06T18:00:00Z',
    latest_version: '1.5.0',
    available: false,
    notes: [],
    can_update: true,
    active_jobs: 0,
    last_run: null,
    ...overrides,
  };
}

export function makeUpdateRun(overrides: Partial<UpdateRun> = {}): UpdateRun {
  return {
    id: 1,
    from_version: '1.5.0',
    target_version: '1.5.1',
    state: 'running',
    message: null,
    created_at: '2026-10-06T18:00:00Z',
    finished_at: null,
    ...overrides,
  };
}
