// Armies, scouts, sites, roads and the hero's quests in a solo session
// (docs/local-engine.md, part 5): scouts sent to a horde, an army led by
// the hero holding a hex on the horde's road and fighting it there, then
// called home; an army exploring an ancient site (no fort on it until it
// is explored); a road built, a fort and a bridge refused; a quest; a camp
// stormed; settlers refused.
import { hexDistance, neighbors, hex } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Armies', displayName: 'You', speed: 50, difficulty: 'normal' };

scenario('army-scenario.json', START, async ({ started, now, play }) => {
  const at = (iso: string) => new Date(iso).getTime();
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const spawnAt = at((started.waves as { spawnAt: string }[])[0]!.spawnAt);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'scout_lodge' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 5 } });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'scout', count: 2 } });
  await play({ method: 'PUT', path: '/v1/villages/1/reinforce', body: { share: 0.3, range: 3 } });
  await play({ method: 'PUT', path: '/v1/villages/1/reinforce', body: { share: 0.3, range: 50 } });
  await play({ advance: spawnAt - now().getTime() - 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 10 } });
  await play({ method: 'POST', path: '/v1/villages/1/scout', body: { waveId: 1, count: 2 } });
  await play({ method: 'POST', path: '/v1/villages/1/scout', body: { waveId: 1, count: 9 } });
  await play({ advance: 21 * MINUTE });
  const first = (await play({ method: 'GET', path: world })).body.waves[0];
  // Hold the hex before the village on the horde's road, the hero leading.
  const [hq, hr] = first.path.at(-2) as [number, number, number];
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: hq, r: hr }, units: { spearman: 7 }, withHero: true } });
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: home.q, r: home.r }, units: { spearman: 1 } } });
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'support', targetVillageId: 1, units: { spearman: 1 } } });
  await play({ advance: at(first.arrivesAt) - now().getTime() + 3 * MINUTE });
  const after = (await play({ method: 'GET', path: world })).body;
  const army = after.armies.find((a: { orders: string }) => a.orders === 'hold');
  if (army) await play({ method: 'POST', path: `/v1/armies/${army.id}/recall`, body: {} });
  // An unguarded site, the nearest one.
  const site = [...after.sites]
    .filter((s: { status: string; guardians: number | null }) => s.status === 'unexplored')
    .sort((a: { q: number; r: number }, b: { q: number; r: number }) => hexDistance(hex(a.q, a.r), hex(home.q, home.r)) - hexDistance(hex(b.q, b.r), hex(home.q, home.r)))[0];
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q: site.q, r: site.r } });
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'explore', target: { q: site.q, r: site.r }, units: { spearman: 2, scout: 1 } } });
  const next = neighbors(hex(home.q, home.r)).find((n) => passable(n.q, n.r))!;
  await play({ method: 'POST', path: '/v1/villages/1/roads', body: { a: { q: home.q, r: home.r }, b: { q: next.q, r: next.r } } });
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q: next.q, r: next.r } });
  await play({ method: 'POST', path: '/v1/villages/1/crossings', body: { a: { q: home.q, r: home.r }, b: { q: next.q, r: next.r } } });
  await play({ advance: 30 * MINUTE });
  const later = (await play({ method: 'GET', path: world })).body;
  const offer = later.heroes[0].offers[0];
  if (offer) await play({ method: 'POST', path: `${world}/hero/quest`, body: { offer: offer.id } });
  const camp = later.camps[0];
  if (camp) await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'clear', target: { q: camp.q, r: camp.r }, units: { spearman: 3 } } });
  await play({ method: 'POST', path: '/v1/villages/1/found', body: { q: home.q + 3, r: home.r } });
  await play({ method: 'POST', path: '/v1/villages/1/found', body: { q: home.q + 1, r: home.r } });
  await play({ advance: 60 * MINUTE });
  await play({ method: 'GET', path: world });
  // Explored, the site is gone from the land: a fort may stand there.
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q: site.q, r: site.r } });
});
