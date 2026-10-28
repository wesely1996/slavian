// Road levels in a solo session: a road built beside the village, then
// improved twice, each level faster to march along; refused while it is
// being built or improved, and once it is as good as it gets. An army
// marches along it at each level.
import { neighbors, hex } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Roads', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('road-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  const next = neighbors(hex(home.q, home.r)).find((n) => passable(n.q, n.r))!;
  const road = () => play({ method: 'POST', path: '/v1/villages/1/roads', body: { a: { q: home.q, r: home.r }, b: { q: next.q, r: next.r } } });
  // An army out to the next hex and back into the village: how long the road takes.
  const march = async () => {
    const army = (await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: next.q, r: next.r }, units: { spearman: 1 } } })).body.army;
    await play({ advance: 2 * MINUTE });
    if (army) await play({ method: 'POST', path: `/v1/armies/${army.id}/move`, body: { villageId: 1 } });
    await play({ advance: 2 * MINUTE });
  };

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 2 } });
  await play({ advance: 10 * MINUTE });
  await march();

  // Built, then improved: each level waits for the work before it.
  await road();
  await road();
  await play({ advance: 2 * MINUTE });
  await march();
  await play({ advance: 60 * MINUTE });
  await road();
  await road();
  await play({ advance: 3 * MINUTE });
  await play({ method: 'GET', path: world });
  await march();
  await play({ advance: 60 * MINUTE });
  await road();
  await play({ advance: 3 * MINUTE });
  await road();
  await play({ method: 'GET', path: world });
  await march();
});
