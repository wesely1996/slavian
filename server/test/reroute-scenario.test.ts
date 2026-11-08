// Armies turned on the road in a solo session: one marching out sent to
// another hex halfway, one marching called home, one coming home sent out
// again to hold a hex, and one in the middle of turning told to go where it
// already heads. Then standing armies moved onto the starter camp (they
// storm it) and onto an ancient site (they search it, slowly without scouts).
// Last, armies told to come home once done: one holding a hex comes straight
// back, one sent to support the village it came from is refused, and one
// standing is told to come home and turns back at once.
import { hex, hexDistance } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Reroute', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('reroute-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  // Open hexes 3 and 4 away, on different sides.
  const ring = (d: number) =>
    [...terrain.keys()]
      .map((k) => k.split(',').map(Number) as [number, number])
      .filter(([q, r]) => passable(q, r) && hexDistance(hex(q, r), hex(home.q, home.r)) === d)
      .sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const [far, other] = [ring(4)[0]!, ring(4).at(-1)!];
  const near = ring(3)[0]!;
  const army = (body: object) => play({ method: 'POST', path: '/v1/villages/1/armies', body });
  const move = (id: number, body: object) => play({ method: 'POST', path: `/v1/armies/${id}/move`, body });

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 8 } });
  await play({ advance: 15 * MINUTE });

  // Sent out, then turned halfway to another hex; told again where it heads.
  const first = (await army({ orders: 'hold', target: { q: far[0], r: far[1] }, units: { spearman: 3 } })).body.army;
  await play({ advance: 30_000 });
  await move(first.id, { target: { q: other[0], r: other[1] } });
  await move(first.id, { target: { q: other[0], r: other[1] } });
  // Another marching out, called home before it gets there.
  const second = (await army({ orders: 'hold', target: { q: far[0], r: far[1] }, units: { spearman: 2 } })).body.army;
  await play({ advance: 20_000 });
  await play({ method: 'POST', path: `/v1/armies/${second.id}/recall`, body: {} });
  await play({ method: 'POST', path: `/v1/armies/${second.id}/recall`, body: {} });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });

  // The first, standing, is called home; on the way it is sent to hold
  // another hex instead, and can't be called home twice.
  await play({ method: 'POST', path: `/v1/armies/${first.id}/recall`, body: {} });
  await play({ advance: 20_000 });
  await play({ method: 'POST', path: `/v1/armies/${first.id}/recall`, body: {} });
  await move(first.id, { target: { q: near[0], r: near[1] } });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });
  // And from there into the village.
  await move(first.id, { villageId: 1 });
  await play({ advance: 20_000 });
  await move(first.id, { target: { q: far[0], r: far[1] } });
  await play({ advance: 10 * MINUTE });
  const standing = (await play({ method: 'GET', path: world })).body;

  // Moved onto the camp, it storms it; another moved onto a site explores it.
  const camp = standing.camps[0] as { q: number; r: number } | undefined;
  if (camp) await move(first.id, { target: { q: camp.q, r: camp.r } });
  const site = (standing.sites as { q: number; r: number; status: string }[])
    .filter((s) => s.status === 'unexplored')
    .sort((a, b) => hexDistance(hex(a.q, a.r), hex(home.q, home.r)) - hexDistance(hex(b.q, b.r), hex(home.q, home.r)))[0];
  const third = (await army({ orders: 'hold', target: { q: near[0], r: near[1] }, units: { spearman: 3 } })).body.army;
  await play({ advance: 10 * MINUTE });
  if (site) await move(third.id, { target: { q: site.q, r: site.r } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 3 * 60 * MINUTE });
  const later = (await play({ method: 'GET', path: world })).body;

  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 6 } });
  await play({ advance: 15 * MINUTE });
  await army({ orders: 'hold', target: { q: near[0], r: near[1] }, units: { spearman: 2 }, returnHome: true });
  const staying = (await army({ orders: 'hold', target: { q: other[0], r: other[1] }, units: { spearman: 2 } })).body.army;
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });
  if (staying) {
    await play({ method: 'POST', path: `/v1/armies/${staying.id}/return-home`, body: { returnHome: true } });
    await play({ method: 'POST', path: `/v1/armies/${staying.id}/return-home`, body: { returnHome: false } });
  }
  const standingArmy = (later.armies as { id: number; status: string }[]).find((a) => a.status === 'stationed');
  if (standingArmy) await play({ method: 'POST', path: `/v1/armies/${standingArmy.id}/return-home`, body: { returnHome: true } });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });
});
