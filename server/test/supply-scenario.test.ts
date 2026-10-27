// Supply points, grain in forts and supply routes in a solo session: a
// supply point built (and the ones refused), a supply route that waits for
// it to stand and then sends grain by caravan; an army standing on it that
// fills up there, leaves grain and takes it back, and eats from it when its
// own grain runs out; a supply point on the first horde's road burned as it
// passes; and grain left in a fort.
import { hex, hexDistance, neighbors } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Supply', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('supply-scenario.json', START, async ({ started, now, play }) => {
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
  const [first, second, third] = [near[0]!, near[1]!, near[2]!];
  const army = (body: object) => play({ method: 'POST', path: '/v1/villages/1/armies', body });

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'caravan_yard' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 6 } });
  await play({ advance: 20 * MINUTE });

  // A supply point beside the village; too far, on the village, or taken: refused.
  await play({ method: 'POST', path: '/v1/villages/1/supply-points', body: { q: home.q + 9, r: home.r } });
  await play({ method: 'POST', path: '/v1/villages/1/supply-points', body: { q: home.q, r: home.r } });
  const point = (await play({ method: 'POST', path: '/v1/villages/1/supply-points', body: { q: first.q, r: first.r } })).body.fort;
  await play({ method: 'POST', path: '/v1/villages/1/supply-points', body: { q: first.q, r: first.r } });
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q: first.q, r: first.r } });

  // A supply route: refused for a store that isn't there or too small a
  // target; placed, it waits until the supply point stands, then sends grain.
  await play({ method: 'POST', path: '/v1/villages/1/orders', body: { kind: 'supply', fortId: 99, target: 1000 } });
  await play({ method: 'POST', path: '/v1/villages/1/orders', body: { kind: 'supply', fortId: point.id, target: 10 } });
  await play({ method: 'POST', path: '/v1/villages/1/orders', body: { kind: 'supply', fortId: point.id, target: 400 } });
  await play({ method: 'POST', path: '/v1/villages/1/orders', body: { kind: 'supply', fortId: point.id, target: 300 } });
  await play({ advance: 3 * MINUTE });
  await play({ method: 'GET', path: world });

  // An army holds the supply point and fills up there; it leaves grain, and
  // takes it back. One on open ground has no store to use.
  const holder = (await army({ orders: 'hold', target: { q: first.q, r: first.r }, units: { spearman: 3 } })).body.army;
  const open = (await army({ orders: 'hold', target: { q: second.q, r: second.r }, units: { spearman: 2 } })).body.army;
  await play({ method: 'POST', path: `/v1/armies/${holder.id}/store`, body: { grain: 50 } });
  await play({ advance: 2 * MINUTE });
  await play({ method: 'POST', path: `/v1/armies/${holder.id}/store`, body: { grain: 50 } });
  await play({ method: 'POST', path: `/v1/armies/${holder.id}/store`, body: { grain: 100000 } });
  await play({ method: 'POST', path: `/v1/armies/${holder.id}/store`, body: { grain: 10 } });
  await play({ method: 'POST', path: `/v1/armies/${holder.id}/resupply`, body: {} });
  await play({ method: 'POST', path: `/v1/armies/${open.id}/store`, body: { grain: 10 } });
  await play({ method: 'POST', path: `/v1/armies/${open.id}/resupply`, body: {} });
  await play({ method: 'POST', path: `/v1/armies/${open.id}/move`, body: { villageId: 1 } });

  // The first horde sets out; a supply point on its road, with no army on
  // it, burns as it passes. The army on the first one eats from its stores
  // when its own grain runs out.
  await play({ advance: Math.max(MINUTE, spawnAt - now().getTime() + 2 * MINUTE) });
  const wave = (await play({ method: 'GET', path: world })).body.waves[0];
  const road = (wave.path ?? []) as [number, number, number][];
  const onRoad = road.find(([q, r]) => {
    const d = hexDistance(hex(q, r), hex(home.q, home.r));
    return d >= 2 && d <= scheduler.data.field.supplyPoint.range && passable(q, r);
  });
  if (onRoad) await play({ method: 'POST', path: '/v1/villages/1/supply-points', body: { q: onRoad[0], r: onRoad[1] } });
  await play({ advance: (wave.arrivesAt ? at(wave.arrivesAt) - now().getTime() : 60 * MINUTE) + 3 * MINUTE });
  await play({ method: 'GET', path: world });

  // Grain in a fort: an army holding one leaves some there and takes it back.
  await play({ advance: 15 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q: third.q, r: third.r } });
  await play({ advance: 2 * MINUTE });
  const keeper = (await army({ orders: 'hold', target: { q: third.q, r: third.r }, units: { spearman: 1 } })).body.army;
  await play({ advance: 2 * MINUTE });
  if (keeper) {
    await play({ method: 'POST', path: `/v1/armies/${keeper.id}/store`, body: { grain: 20 } });
    await play({ method: 'POST', path: `/v1/armies/${keeper.id}/resupply`, body: {} });
  }
  await play({ method: 'GET', path: world });
});
