// Military caravans and the military reserve in a solo session: the reserve
// filled from the granary as buildings and troops are done; an army that
// leaves with grain from it alone, its wagons carrying more; wagons drawn
// into a ring on open ground (and the ones refused); a horde that runs into
// the wagon fort; and the army marching back into the garrison, its grain
// going into the reserve.
import { hex, hexDistance, neighbors } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Wagons', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('wagons-scenario.json', START, async ({ started, now, play }) => {
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

  // The barracks and the stables fill the reserve as they are done; the
  // caravans and spearmen as they are trained.
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'stables' } });
  await play({ advance: 50 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'stables' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'supply_wagon', count: 2 } });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 5 } });
  await play({ advance: 20 * MINUTE });
  const before = (await play({ method: 'GET', path: world })).body;

  // Spearmen alone can't circle wagons.
  const foot = (await army({ orders: 'hold', target: { q: near[1]!.q, r: near[1]!.r }, units: { spearman: 2 } })).body.army;
  await play({ advance: 5 * MINUTE });
  await play({ method: 'POST', path: `/v1/armies/${foot.id}/wagon-fort`, body: {} });
  await play({ method: 'POST', path: `/v1/armies/${foot.id}/move`, body: { villageId: 1 } });

  // The caravans' army holds a hex on the first horde's road (as forecast),
  // with grain from the reserve and more in its wagons; it circles its
  // wagons once it stands there, and only once.
  const forecast = before.waves[0].forecast;
  const road = (forecast?.path ?? []) as [number, number, number][];
  const onRoad = road.find(([q, r]) => {
    const d = hexDistance(hex(q, r), hex(home.q, home.r));
    return d >= 1 && d <= 3 && passable(q, r);
  });
  const cell = onRoad ? { q: onRoad[0], r: onRoad[1] } : { q: near[0]!.q, r: near[0]!.r };
  const ring = (await army({ orders: 'hold', target: cell, units: { spearman: 3, supply_wagon: 2 } })).body.army;
  await play({ method: 'POST', path: `/v1/armies/${ring.id}/wagon-fort`, body: {} });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'POST', path: `/v1/armies/${ring.id}/wagon-fort`, body: {} });
  await play({ method: 'POST', path: `/v1/armies/${ring.id}/wagon-fort`, body: {} });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });

  // The horde runs into the wagon fort.
  const arrives = forecast?.arrivesAt ? at(forecast.arrivesAt) : spawnAt + 10 * MINUTE;
  await play({ advance: Math.max(MINUTE, arrives - now().getTime() + 3 * MINUTE) });
  await play({ method: 'GET', path: world });

  // What is left marches home: its grain goes into the reserve.
  const after = (await play({ method: 'GET', path: world })).body.armies.find((a: { id: number }) => a.id === ring.id);
  if (after?.status === 'stationed') await play({ method: 'POST', path: `/v1/armies/${ring.id}/move`, body: { villageId: 1 } });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });
});
