import { strings } from '../strings';

const pad = (n: number) => String(n).padStart(2, '0');

/** `182` → `3:02`; `3725` → `1:02:05`; `null` → `—`. */
export function formatDuration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined || !Number.isFinite(seconds)) return '—';
  const total = Math.max(0, Math.round(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return h > 0 ? `${String(h)}:${pad(m)}:${pad(s)}` : `${String(m)}:${pad(s)}`;
}

/** Tempo do transport, com décimos: `72.43` → `1:12.4`. */
export function formatClock(seconds: number): string {
  const tenths = Math.max(0, Math.floor((Number.isFinite(seconds) ? seconds : 0) * 10));
  const m = Math.floor(tenths / 600);
  const s = Math.floor((tenths % 600) / 10);
  return `${String(m)}:${pad(s)}.${String(tenths % 10)}`;
}

/** Loudness/pico: `-10.64` → `−10.6`; com `signed`, `0.9` → `+0.9`. */
export function formatDb(value: number, signed = false): string {
  const sign = value < 0 ? '−' : signed && value > 0 ? '+' : '';
  return `${sign}${Math.abs(value).toFixed(1)}`;
}

/** ETA curta: `~40s`, `~2 min`, `~1 h 5 min`. */
export function formatEta(seconds: number | null | undefined): string | null {
  if (seconds === null || seconds === undefined || !Number.isFinite(seconds)) return null;
  const s = Math.max(1, Math.round(seconds));
  if (s < 60) return `~${String(s)}s`;
  const minutes = Math.round(s / 60);
  if (minutes < 60) return `~${String(minutes)} min`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m > 0 ? `~${String(h)} h ${String(m)} min` : `~${String(h)} h`;
}

function sameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

/** Data curta da biblioteca: `hoje`, `ontem`, `09/09` ou `09/09/25` em outro ano. */
export function formatShortDate(iso: string, now: Date = new Date()): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '—';
  if (sameDay(date, now)) return strings.time.today;
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (sameDay(date, yesterday)) return strings.time.yesterday;
  const dm = `${pad(date.getDate())}/${pad(date.getMonth() + 1)}`;
  return date.getFullYear() === now.getFullYear() ? dm : `${dm}/${pad(date.getFullYear() % 100)}`;
}

/** Data de um export: `hoje 21:14` no mesmo dia; senão a data curta. */
export function formatStampDate(iso: string, now: Date = new Date()): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '—';
  if (!sameDay(date, now)) return formatShortDate(iso, now);
  return `${strings.time.today} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** Tamanho de arquivo: `7100000` → `7,1 MB`; abaixo de 1 MB, em kB. */
export function formatBytes(bytes: number | null | undefined): string {
  if (bytes === null || bytes === undefined || !Number.isFinite(bytes)) return '—';
  if (bytes < 1_000_000) return `${String(Math.max(1, Math.round(bytes / 1000)))} kB`;
  return `${(bytes / 1_000_000).toFixed(1).replace('.', ',')} MB`;
}

/** Tempo relativo curto: `agora há pouco`, `há 3 min`, `há 2 h`, depois a data curta. */
export function formatAgo(iso: string, now: Date = new Date()): string {
  const date = new Date(iso);
  const diff = Math.max(0, now.getTime() - date.getTime());
  const minutes = Math.floor(diff / 60_000);
  if (minutes < 1) return strings.time.justNow;
  if (minutes < 60) return strings.time.minutesAgo(minutes);
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return strings.time.hoursAgo(hours);
  return formatShortDate(iso, now);
}
