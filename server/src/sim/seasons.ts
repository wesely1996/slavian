// Seasons (data/seasons.json): one game day each, in turn from the run's
// start. Spring changes nothing; summer doubles the grain, winter stops it,
// autumn toughens every soldier, and each season favours some fronts.
import type { GameData, Season } from '../data/index.js';
import type { Front } from './mapgen.js';
const MS_PER_HOUR = 3_600_000;

export interface SeasonAt {
  readonly season: Season;
  // Game days since the start (0 for the first).
  readonly day: number;
  readonly startsAt: Date;
  readonly endsAt: Date;
}

export function dayMs(data: GameData, worldSpeed: number): number {
  return (data.seasons.dayHours * MS_PER_HOUR) / worldSpeed;
}

// The season at `at` in a world that started at `startedAt` (before the
// start: its first season).
export function seasonAt(data: GameData, world: { startedAt: Date | null; speed: number }, at: Date): SeasonAt {
  const start = world.startedAt ?? at;
  const length = dayMs(data, world.speed);
  const day = Math.max(0, Math.floor((at.getTime() - start.getTime()) / length));
  const startsAt = new Date(start.getTime() + day * length);
  return { season: data.seasons.order[day % data.seasons.order.length]!, day, startsAt, endsAt: new Date(startsAt.getTime() + length) };
}

// What a season adds to every unit's defense in battle, as a factor.
export function seasonDefense(data: GameData, season: Season): number {
  return 1 + data.seasons.seasons[season].defense;
}

// The settlement bonus a season gives (added to the village's bonuses as
// `season.grain`; none in spring).
export function seasonBonuses(data: GameData, season: Season): Record<string, number> {
  const grain = data.seasons.seasons[season].grain;
  return grain === 0 ? {} : { 'season.grain': grain };
}

// How likely a front is to send a horde in `season`.
export function frontWeight(data: GameData, season: Season, front: Front): number {
  return data.seasons.seasons[season].fronts[front] ?? 1;
}
