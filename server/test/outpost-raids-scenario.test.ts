// Hordes and outposts in a solo session (horde.json outposts): a horde
// burns an outpost only by marching onto it, and its supplies swell the
// horde. Setting out, the first horde weighs the village's outposts: a rich
// one (level 5) beside its road is worth the detour, a poor one (level 1)
// may not be; it burns what lies on its road and lays siege.
import { hex, hexDistance } from '../src/sim/hex.js';
import type { TerrainId } from '../src/data/index.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 6262, at: '2026-06-01T08:00:00.000Z', name: 'Outposts', displayName: 'You', speed: 50, difficulty: 'baron' };

scenario('outpost-raids-scenario.json', START, async ({ started, play }) => {
  const home = started.villages[0] as { q: number; r: number };
  const yields = scheduler.data.buildings.buildings.outpost!.yields ?? {};
  // The first horde's expected road (the forecast).
  const road = (started.waves[0].forecast.path as [number, number, number][]).map(([q, r]) => hex(q, r));
  const off = (cell: { q: number; r: number }) => Math.min(...road.map((step) => hexDistance(step, cell)));
  const taken = [...(started.camps as { q: number; r: number }[]), ...(started.villages as { q: number; r: number }[]), hex(0, 0)];
  const sites = (started.map.hexes as [number, number, TerrainId][])
    .filter(([q, r, terrain]) => terrain in yields && hexDistance(hex(q, r), hex(home.q, home.r)) <= 2)
    .filter(([q, r]) => !taken.some((c) => c.q === q && c.r === r) && off(hex(q, r)) > 0)
    .sort((a, b) => off(hex(a[0], a[1])) - off(hex(b[0], b[1])) || a[0] - b[0] || a[1] - b[1]);
  if (sites.length < 2) throw new Error('No room for two outposts');
  // The rich one as near the road as can be, the poor one as far.
  const [q1, r1, t1] = sites[0]!;
  const [q2, r2, t2] = sites.at(-1)!;
  await play({
    set: {
      plots: {
        [`o${q1},${r1}`]: { building: 'outpost', level: 5, terrain: t1 },
        [`o${q2},${r2}`]: { building: 'outpost', level: 1, terrain: t2 },
      },
    },
  });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  const spawnIn = new Date(started.waves[0].spawnAt).getTime() - new Date(START.at).getTime();
  await play({ advance: spawnIn + MINUTE });
  const marching = await play({ method: 'GET', path: '/v1/worlds/-1' });
  const arriveIn = new Date(marching.body.waves[0].arrivesAt).getTime() - new Date(marching.body.serverTime).getTime();
  await play({ advance: Math.max(MINUTE, arriveIn / 2) });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ advance: Math.max(MINUTE, arriveIn / 2) + MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: '/v1/worlds/-1' });
}, 60_000);
