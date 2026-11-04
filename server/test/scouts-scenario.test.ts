// Scouts of every kind in a solo session: pathfinders and assassins
// (trained at a higher Scout Lodge, set into the garrison here) go out
// together to the first horde once it has set out under its leader; the
// assassins may kill the leader. Refused: soldiers sent scouting, no scouts
// at all. Then scouts march with an army holding a hex on the horde's road:
// they stand aside in the fight and give the army their intel.
import { hex, hexDistance, neighbors } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Scouts', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('scouts-scenario.json', START, async ({ started, now, play }) => {
  const at = (iso: string) => new Date(iso).getTime();
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const spawnAt = at((started.waves as { spawnAt: string }[])[0]!.spawnAt);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  const scout = (body: object) => play({ method: 'POST', path: '/v1/villages/1/scout', body });

  await play({ set: { garrison: { scout: 4, pathfinder: 4, assassin: 16, spearman: 8 } } });
  // Before the horde sets out, scouts sent out of the village start eating.
  await play({ advance: spawnAt - now().getTime() - 15 * MINUTE });
  const before = (await play({ method: 'GET', path: world })).body;
  const waveId = before.waves[0].id;
  await scout({ waveId, units: { spearman: 1 } });
  await scout({ waveId, units: {} });
  await scout({ waveId, count: 0 });

  // Scouts hold a hex on the horde's road with spearmen (the hex on it
  // nearest the village, not the Holy City at its end).
  const road = (before.waves[0].forecast?.path ?? []) as [number, number, number][];
  const onRoad = road
    .slice(0, -1)
    .filter(([q, r]) => passable(q, r) && hexDistance(hex(q, r), hex(home.q, home.r)) >= 1)
    .sort((a, b) => hexDistance(hex(a[0], a[1]), hex(home.q, home.r)) - hexDistance(hex(b[0], b[1]), hex(home.q, home.r)))[0];
  const near = neighbors(hex(home.q, home.r)).find((n) => passable(n.q, n.r))!;
  const cell = onRoad ? { q: onRoad[0], r: onRoad[1] } : { q: near.q, r: near.r };
  await play({ advance: 10 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: cell, units: { scout: 4 } } });
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: cell, units: { spearman: 8, scout: 4 } } });

  // Once it has set out under its leader: pathfinders and assassins together.
  await play({ advance: 6 * MINUTE });
  await scout({ waveId, units: { pathfinder: 4, assassin: 16 } });
  await play({ method: 'GET', path: world });
  for (let i = 0; i < 8; i++) {
    await play({ advance: 30_000 });
    await play({ method: 'GET', path: world });
  }
  await play({ advance: 20 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ method: 'GET', path: `${world}/notifications` });
});
