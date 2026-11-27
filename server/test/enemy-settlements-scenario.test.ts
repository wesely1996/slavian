// The enemy's settlements in a solo session (enemy-lands.json settlements):
// rivers run through each front's lands from the start, and each front
// founds its seat at once (its lair, in the North). Every few game hours
// each settlement builds: palisades all round, then its moat, then raises
// its walls. Two game days on, the next settlement (a town) is founded a
// band nearer, and runs its road to the seat, bridging rivers on the way.
// Settlements in bands still in fog aren't shown.
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Enemy', displayName: 'You', speed: 50, difficulty: 'baron' };
const HOUR = (60 * MINUTE) / START.speed;

scenario('enemy-settlements-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const rules = scheduler.data.enemyLands.settlements;
  // Only the first band is seen: no settlement shows yet.
  await play({ method: 'GET', path: world });
  for (const front of started.map.activeFronts as string[]) await play({ set: { enemySight: { front, bands: 4 } } });
  await play({ method: 'GET', path: world });
  for (let i = 0; i < 6; i++) {
    await play({ advance: rules.worksEveryHours * HOUR });
    await play({ method: 'GET', path: world });
  }
  const day = scheduler.data.seasons.dayHours * HOUR;
  await play({ advance: rules.everyDays * day - 6 * rules.worksEveryHours * HOUR + MINUTE });
  await play({ method: 'GET', path: world });
  for (let i = 0; i < 12; i++) await play({ advance: rules.worksEveryHours * HOUR });
  await play({ method: 'GET', path: world });
}, 60_000);
