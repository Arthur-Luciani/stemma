import type { SystemUpdate } from '../../api/types';
import { strings } from '../../strings';

/** Quanto tempo o "atualizado para vX" continua aparecendo depois do fim. */
export const RECENT_MS = 15 * 60 * 1000;

export type UpdateView =
  /** Atualização em andamento (o servidor pode estar fora do ar). */
  | { kind: 'running'; target: string }
  /** Acabou de atualizar para a versão no ar. */
  | { kind: 'updated'; version: string }
  /** Há versão nova; `lastFailure` = motivo da última tentativa, se ela falhou. */
  | { kind: 'available'; target: string; lastFailure: string | null }
  | { kind: 'upToDate' }
  | { kind: 'unknown' };

export function updateView(data: SystemUpdate, now = Date.now()): UpdateView {
  const run = data.last_run;
  if (run?.state === 'running') return { kind: 'running', target: run.target_version };
  // Versão mais nova que a do "atualizado agora há pouco" ganha: o aviso não pode sumir.
  if (data.available && data.latest_version) {
    const lastFailure =
      run?.state === 'failed' ? failureText(run.message, data.current_version) : null;
    return { kind: 'available', target: data.latest_version, lastFailure };
  }
  if (
    run?.state === 'succeeded' &&
    run.target_version === data.current_version &&
    run.finished_at &&
    now - Date.parse(run.finished_at) < RECENT_MS
  ) {
    return { kind: 'updated', version: data.current_version };
  }
  return data.check === 'ok' ? { kind: 'upToDate' } : { kind: 'unknown' };
}

/** O motivo da falha, sempre dizendo que a versão anterior continua no ar. */
export function failureText(message: string | null, current: string): string {
  const still = strings.update.stillRunning(current);
  if (!message) return still;
  return message.includes('continua no ar') ? message : `${message} ${still}`;
}

/** Aviso (chip/faixa) aparece com versão nova ou com a atualização em andamento. */
export function showsNotice(view: UpdateView): view is Extract<UpdateView, { target: string }> {
  return view.kind === 'available' || view.kind === 'running';
}
