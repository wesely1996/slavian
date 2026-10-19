// When to bother a player: quiet hours and the daily digest, in their local
// time (a fixed UTC offset the app reports).
const MS_PER_MINUTE = 60_000;
const MINUTES_PER_DAY = 1440;

export interface NotifyPrefs {
  // Minutes after local midnight; null: no quiet hours.
  readonly quietStart: number | null;
  readonly quietEnd: number | null;
  readonly utcOffsetMinutes: number;
  readonly digestHour: number;
}

export const DEFAULT_PREFS: NotifyPrefs = { quietStart: null, quietEnd: null, utcOffsetMinutes: 0, digestHour: 18 };

function localMinute(at: Date, prefs: NotifyPrefs): number {
  const minutes = Math.floor(at.getTime() / MS_PER_MINUTE) + prefs.utcOffsetMinutes;
  return ((minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
}

export function inQuietHours(at: Date, prefs: NotifyPrefs): boolean {
  const { quietStart: start, quietEnd: end } = prefs;
  if (start === null || end === null || start === end) return false;
  const m = localMinute(at, prefs);
  return start < end ? m >= start && m < end : m >= start || m < end;
}

// The next moment at the player's digest hour, strictly after `after`.
export function nextDigestAt(after: Date, prefs: NotifyPrefs): Date {
  const m = localMinute(after, prefs);
  let wait = prefs.digestHour * 60 - m;
  if (wait <= 0) wait += MINUTES_PER_DAY;
  const exact = Math.floor(after.getTime() / MS_PER_MINUTE) * MS_PER_MINUTE;
  return new Date(exact + wait * MS_PER_MINUTE);
}

// "3 builds finished, 1 tech researched, …" from the kinds of what happened.
export function digestSummary(kinds: readonly string[]): string {
  const labels: Record<string, [string, string]> = {
    build_done: ['build finished', 'builds finished'],
    research_done: ['tech researched', 'techs researched'],
    battle_result: ['battle report', 'battle reports'],
    caravan_delivered: ['caravan delivery', 'caravan deliveries'],
    settlers: ['settlers report', 'settlers reports'],
    hero: ['hero report', 'hero reports'],
    leader: ['word of an enemy leader', 'words of enemy leaders'],
  };
  const counts = new Map<string, number>();
  for (const kind of kinds) counts.set(kind, (counts.get(kind) ?? 0) + 1);
  return [...counts.entries()]
    .map(([kind, n]) => {
      const [one, many] = labels[kind] ?? ['update', 'updates'];
      return `${n} ${n === 1 ? one : many}`;
    })
    .join(', ');
}
