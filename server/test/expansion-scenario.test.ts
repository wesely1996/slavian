// Founding a second village in a solo session (docs/local-engine.md,
// part 5): settlers trained one by one and sent out; then the hero moves
// there, a caravan and an army go between the villages, a road and a fort
// rise, and the hordes keep coming. The new village is given up (refused
// while an army guards it), and the first can't be.
import { hexDistance, hex, spiral } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Kin', displayName: 'You', speed: 50, difficulty: 'story' };

scenario('expansion-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const settleable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`) as keyof typeof scheduler.data.terrain.terrain | undefined;
    return t !== undefined && scheduler.data.terrain.terrain[t].settleable;
  };
  const sites = started.sites as { q: number; r: number }[];
  // A free settleable hex four hexes out, away from the Holy City.
  const spot = spiral(hex(home.q, home.r), 4).find(
    (c) => hexDistance(c, hex(home.q, home.r)) === 4 && hexDistance(c, hex(0, 0)) >= 3 && settleable(c.q, c.r) && !sites.some((s) => s.q === c.q && s.r === c.r),
  )!;

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'settlers_lodge' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'barracks' } });
  let settlers = 0;
  for (let i = 0; i < 12 && settlers < 3; i++) {
    await play({ advance: 20 * MINUTE });
    const answer = await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'settler', count: 1 } });
    if (answer.status === 200) settlers++;
  }
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/found', body: { q: spot.q, r: spot.r, name: 'Novgorod' } });
  await play({ advance: 30 * MINUTE });
  const founded = (await play({ method: 'GET', path: world })).body;
  const second = founded.villages.find((v: { name: string }) => v.name === 'Novgorod');
  if (second) {
    await play({ method: 'POST', path: `${world}/hero/move`, body: { villageId: second.id } });
    await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 4 } });
    await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c4', building: 'caravan_yard' } });
    await play({ advance: 20 * MINUTE });
    await play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationVillageId: second.id, load: { wood: 100, stone: 0, grain: 50, iron: 0 } } });
    await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'support', targetVillageId: second.id, units: { spearman: 2 } } });
    await play({ method: 'PUT', path: `/v1/villages/${second.id}/reinforce`, body: { share: 1, range: 6 } });
    await play({ advance: 30 * MINUTE });
    const settled = (await play({ method: 'GET', path: world })).body;
    // Given up: refused while an army guards it, then once it has gone home.
    await play({ method: 'POST', path: `/v1/villages/${second.id}/abandon`, body: {} });
    for (const army of (settled.armies as { id: number; status: string; targetVillageId: number | null }[]).filter((a) => a.targetVillageId === second.id && a.status === 'stationed')) {
      await play({ method: 'POST', path: `/v1/armies/${army.id}/recall`, body: {} });
    }
    await play({ advance: 30 * MINUTE });
    await play({ method: 'POST', path: `/v1/villages/${second.id}/abandon`, body: {} });
  }
  const near = spiral(hex(home.q, home.r), 1).find((c) => hexDistance(c, hex(home.q, home.r)) === 1 && settleable(c.q, c.r))!;
  await play({ method: 'POST', path: '/v1/villages/1/roads', body: { a: { q: home.q, r: home.r }, b: { q: near.q, r: near.r } } });
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q: near.q, r: near.r } });
  // The first village can't be given up: there is nowhere left to go.
  await play({ method: 'POST', path: '/v1/villages/1/abandon', body: {} });
  for (let i = 0; i < 4; i++) {
    await play({ advance: 45 * MINUTE });
    await play({ method: 'GET', path: world });
  }
});
