import { formatAgo, formatDuration, formatEta, formatShortDate } from './format';

describe('formatadores', () => {
  it('duração', () => {
    expect(formatDuration(182)).toBe('3:02');
    expect(formatDuration(3725)).toBe('1:02:05');
    expect(formatDuration(null)).toBe('—');
  });

  it('ETA', () => {
    expect(formatEta(40)).toBe('~40s');
    expect(formatEta(130)).toBe('~2 min');
    expect(formatEta(3900)).toBe('~1 h 5 min');
    expect(formatEta(null)).toBeNull();
  });

  it('data curta e tempo relativo', () => {
    const now = new Date(2026, 9, 5, 21, 14);
    expect(formatShortDate(new Date(2026, 9, 5, 8).toISOString(), now)).toBe('hoje');
    expect(formatShortDate(new Date(2026, 9, 4, 23).toISOString(), now)).toBe('ontem');
    expect(formatShortDate(new Date(2026, 8, 9).toISOString(), now)).toBe('09/09');
    expect(formatShortDate(new Date(2025, 8, 9).toISOString(), now)).toBe('09/09/25');
    expect(formatAgo(new Date(2026, 9, 5, 21, 11).toISOString(), now)).toBe('há 3 min');
    expect(formatAgo(new Date(2026, 9, 5, 21, 14).toISOString(), now)).toBe('agora mesmo');
  });
});
