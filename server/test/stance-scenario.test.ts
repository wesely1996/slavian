// Army stances in a solo session: two armies hold the same hex on the first
// horde's road, each in its own stance: one sent out Offensive, one sent
// in the village's stance and set to Hold the Line where it stands. The
// horde runs into them; the Offensive army breaks first and falls back
// home while the other fights on. A stance can't be changed in the middle
// of the battle, nor for an army on its way home.
import { hex, hexDistance, neighbors } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Stances', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('stance-scenario.json', START, async ({ started, now, play }) => {
  const at = (iso: string) => new Date(iso).getTime();
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const spawnAt = at((started.waves as { spawnAt: string }[])[0]!.spawnAt);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  const near = neighbors(hex(home.q, home.r)).filter((n) => passable(n.q, n.r));
  const army = (body: object) => play({ method: 'POST', path: '/v1/villages/1/armies', body });
  const stance = (id: number, value: string) => play({ method: 'POST', path: `/v1/armies/${id}/stance`, body: { stance: value } });

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 8 } });
  // Out shortly before the horde sets out (an army's grain lasts a day).
  await play({ advance: spawnAt - now().getTime() - 15 * MINUTE });
  const before = (await play({ method: 'GET', path: world })).body;

  // Both hold a hex on the first horde's road (as forecast).
  const road = (before.waves[0].forecast?.path ?? []) as [number, number, number][];
  // The hex on it nearest the village (not the Holy City at its end).
  const onRoad = road
    .slice(0, -1)
    .filter(([q, r]) => passable(q, r) && hexDistance(hex(q, r), hex(home.q, home.r)) >= 1)
    .sort((a, b) => hexDistance(hex(a[0], a[1]), hex(home.q, home.r)) - hexDistance(hex(b[0], b[1]), hex(home.q, home.r)))[0];
  const cell = onRoad ? { q: onRoad[0], r: onRoad[1] } : { q: near[0]!.q, r: near[0]!.r };
  const steady = (await army({ orders: 'hold', target: cell, units: { spearman: 6 } })).body.army;
  const bold = (await army({ orders: 'hold', target: cell, units: { spearman: 2 }, stance: 'offensive' })).body.army;
  await play({ advance: 5 * MINUTE });
  if (steady) await stance(steady.id, 'hold_the_line');
  await play({ method: 'GET', path: world });

  // The horde runs into them (when it reaches the hex): round by round.
  const step = onRoad ? spawnAt + onRoad[2] : spawnAt + 10 * MINUTE;
  await play({ advance: Math.max(MINUTE, step - now().getTime() - 10_000) });
  await play({ method: 'GET', path: world });
  for (let i = 0; i < 8; i++) {
    await play({ advance: 20_000 });
    const armies = (await play({ method: 'GET', path: world })).body.armies as { id: number; status: string }[];
    const fighting = armies.find((a) => a.status === 'engaged');
    const back = armies.find((a) => a.status === 'returning');
    if (i === 1 && fighting) await stance(fighting.id, 'balanced');
    if (i === 1 && back) await stance(back.id, 'defensive');
  }
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });
});
