// Caravans that bring back, in a solo session: a supply point next door
// stocked by caravan, and caravans bringing grain back from it, refused
// from the vault. (The Market's bounty board trades between players: a
// solo world has none.)
import { neighbors, hex } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4545, at: '2026-06-01T08:00:00.000Z', name: 'Market', displayName: 'You', speed: 10, difficulty: 'normal' };

scenario('market-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  const load = (wood = 0, stone = 0, grain = 0, iron = 0) => ({ wood, stone, grain, iron });

  await play({ set: { amounts: { wood: 2000, stone: 2000, grain: 1000, iron: 1000 } } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'market' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'caravan_yard' } });
  await play({ advance: 30 * MINUTE });
  await play({ set: { amounts: { wood: 2000, stone: 2000, grain: 1000, iron: 1000 } } });
  await play({ method: 'GET', path: world });

  // A supply point next door, stocked by caravan; then grain brought back from it.
  const next = neighbors(hex(home.q, home.r)).find((n) => passable(n.q, n.r) && !(started.camps as { q: number; r: number }[]).some((c) => c.q === n.q && c.r === n.r))!;
  await play({ method: 'POST', path: '/v1/villages/1/supply-points', body: { q: next.q, r: next.r } });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationFortId: 1, destinationVillageId: null, load: load(0, 0, 300), retrieve: load(0, 100) } });
  await play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationFortId: 1, destinationVillageId: null, load: load(0, 0, 300) } });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationVillageId: null, load: load(50), retrieve: load(0, 50) } });
  await play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationFortId: 1, destinationVillageId: null, load: load(), retrieve: load(0, 0, 120) } });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
});
