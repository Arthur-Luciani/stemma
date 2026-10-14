import type { YtDlpStatus } from '../../api/types';
import { RECENT_MS } from '../update/status';

/**
 * Erros do download e da busca que costumam ser yt-dlp velho: o app sugere atualizar.
 * Os códigos vêm de `map_ytdlp_error` (backend/app/pipeline/download.py).
 */
const OUTDATED_ERRORS: ReadonlySet<string> = new Set([
  'ytdlp_outdated',
  'youtube_format_unavailable',
]);

export function suggestsYtDlpUpdate(code: string | null | undefined): boolean {
  return code != null && OUTDATED_ERRORS.has(code);
}

export type YtDlpView =
  /** Atualização em andamento (o servidor pode estar fora do ar). */
  | { kind: 'running'; target: string }
  /** Acabou de atualizar para a versão no ar. */
  | { kind: 'updated'; version: string }
  /** Há versão nova; `lastFailure` = motivo da última tentativa, se ela falhou. */
  | { kind: 'available'; target: string; lastFailure: string | null }
  | { kind: 'upToDate' }
  | { kind: 'unknown' };

export function ytdlpView(data: YtDlpStatus, now = Date.now()): YtDlpView {
  const run = data.last_run;
  if (run?.state === 'running') return { kind: 'running', target: run.target_version };
  if (data.available && data.latest_version) {
    const lastFailure = run?.state === 'failed' ? run.message : null;
    return { kind: 'available', target: data.latest_version, lastFailure };
  }
  if (
    run?.state === 'succeeded' &&
    run.finished_at &&
    now - Date.parse(run.finished_at) < RECENT_MS
  ) {
    return { kind: 'updated', version: data.installed_version };
  }
  return data.check === 'ok' ? { kind: 'upToDate' } : { kind: 'unknown' };
}
