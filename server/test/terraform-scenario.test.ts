// Terraforming in a solo session: trees planted on plains and hills beside
// the village, paid in grain at once and grown after their hours; the new
// forest then cleared, its timber brought home. Refused too far away, on
// land the work doesn't fit, twice on one hex, and on an outpost. Then a
// wetland made, a lake, and a river dug on from one already there.
import { hex, hexDistance, hexKey, neighbors } from '../src/sim/hex.js';
import { edgeKey, edgesMeet } from '../src/sim/land.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Terraforming', displayName: 'You', speed: 50, difficulty: 'baron' };

scenario('terraform-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = hex(started.villages[0].q, started.villages[0].r);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const taken = new Set<string>([
    ...started.sites.map((s: { q: number; r: number }) => `${s.q},${s.r}`),
    ...started.camps.map((c: { q: number; r: number }) => `${c.q},${c.r}`),
  ]);
  const cells = [...terrain.keys()].map((k) => k.split(',').map(Number) as [number, number]).map(([q, r]) => hex(q, r));
  const at = (kind: string, d: number) => cells.find((c) => terrain.get(`${c.q},${c.r}`) === kind && hexDistance(c, home) === d && !taken.has(`${c.q},${c.r}`))!;
  const plains = at('plains', 1);
  const hills = at('hills', 1);
  const far = at('plains', 3);
  const work = (cell: { q: number; r: number }, action: string) => play({ method: 'POST', path: '/v1/villages/1/terraform', body: { q: cell.q, r: cell.r, action } });

  await play({ set: { amounts: { wood: 100, stone: 1000, grain: 2000, iron: 1000 } } });
  await work(far, 'plant');
  await work(plains, 'drain');
  await work(plains, 'clear');
  await work(plains, 'plant');
  await work(plains, 'plant');
  await work(hills, 'plant');
  await work(home, 'plant');
  await play({ method: 'GET', path: world });
  // Grown: the plains are a forest now, the hills wooded.
  await play({ advance: 21 * MINUTE });
  await play({ method: 'GET', path: world });
  // Cleared again: its timber comes home.
  await work(plains, 'clear');
  await play({ advance: 11 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });
  // An outpost on the cleared land: no work there any more.
  await play({ method: 'POST', path: '/v1/villages/1/outposts', body: { q: plains.q, r: plains.r } });
  await work(plains, 'plant');
  await play({ method: 'GET', path: world });

  // Hills levelled: their stone comes home.
  const hill = cells.find((c) => terrain.get(`${c.q},${c.r}`) === 'hills' && hexDistance(c, home) === 1 && (c.q !== hills.q || c.r !== hills.r))!;
  await play({ set: { amounts: { wood: 0, stone: 0, grain: 5000, iron: 1000 } } });
  await work(hill, 'level');
  // A grove planted round a hex beside the village, an outpost in it, then
  // set alight: nothing passes while it burns, and the fire spreads
  // through the trees.
  const origin = cells.find((c) => terrain.get(`${c.q},${c.r}`) === 'plains' && hexDistance(c, home) === 1 && (c.q !== plains.q || c.r !== plains.r))!;
  const grove = [origin, ...neighbors(origin).filter((c) => ['plains', 'hills'].includes(terrain.get(`${c.q},${c.r}`)!) && hexDistance(c, home) >= 1 && hexDistance(c, home) <= 2 && !taken.has(`${c.q},${c.r}`) && (c.q !== plains.q || c.r !== plains.r))];
  for (const c of grove) await work(c, 'plant');
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ method: 'POST', path: '/v1/villages/1/outposts/abandon', body: { q: plains.q, r: plains.r } });
  await play({ method: 'POST', path: '/v1/villages/1/outposts', body: { q: grove[1]!.q, r: grove[1]!.r } });
  await play({ advance: 30 * MINUTE });
  await play({ set: { garrison: { spearman: 2 } } });
  await play({ advance: MINUTE });
  await work(origin, 'burn');
  await play({ method: 'GET', path: world });
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: origin.q, r: origin.r }, units: { spearman: 1 } } });
  await play({ advance: 2 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });

  // A wetland, a lake, and a river dug on (field.json terraform soak, flood, river).
  await play({ set: { amounts: { wood: 1000, stone: 1000, grain: 5000, iron: 1000 } } });
  const now = (await play({ method: 'GET', path: world })).body;
  const land = new Map<string, string>((now.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const busy = new Set<string>([...taken, ...(now.map.terraforms as [number, number][]).map(([q, r]) => `${q},${r}`), ...grove.map(hexKey), hexKey(plains)]);
  const open = (c: { q: number; r: number }, d: number) => land.get(hexKey(c)) === 'plains' && hexDistance(c, home) === d && !busy.has(hexKey(c));
  const wet = cells.find((c) => open(c, 2))!;
  await work(wet, 'soak');
  busy.add(hexKey(wet));
  const pond = cells.find((c) => open(c, 2))!;
  await work(pond, 'flood');
  busy.add(hexKey(pond));
  // On from a river: one laid beside the village, dug on corner to corner.
  const ground = ['plains', 'forest', 'hills', 'wooded_hills', 'swamp'];
  const isLand = (c: { q: number; r: number }) => ground.includes(land.get(hexKey(c)) ?? '');
  const bank = cells.find((c) => hexDistance(c, home) === 1 && isLand(c) && !busy.has(hexKey(c)))!;
  const other = neighbors(bank).find((n) => isLand(n) && neighbors(n).some((m) => isLand(m) && neighbors(bank).some((x) => hexKey(x) === hexKey(m))))!;
  const toward = neighbors(bank).find((m) => isLand(m) && edgesMeet(bank, other, bank, m) && edgeKey(bank, m) !== edgeKey(bank, other))!;
  await play({ set: { river: { a: bank, b: other } } });
  const river = (body: object) => play({ method: 'POST', path: '/v1/villages/1/terraform', body });
  // Without a neighbour to run toward, or nowhere near a river: refused.
  await river({ q: bank.q, r: bank.r, action: 'river' });
  await river({ q: bank.q, r: bank.r, action: 'river', toward: neighbors(bank).find((m) => !edgesMeet(bank, other, bank, m) && hexKey(m) !== hexKey(other))! });
  await river({ q: bank.q, r: bank.r, action: 'river', toward });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
});
