// Forest fires in a solo session (field.json terraform burn): a ring of
// woods planted round the village, then fires set in the way of what is on
// the road: an army, a caravan, settlers and a horde each finish the hex
// they are crossing and go round the fire to where they were going. No fire
// can be set where an army stands.
import { hex, hexDistance, type Hex } from '../src/sim/hex.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Fires', displayName: 'You', speed: 50, difficulty: 'baron' };

type Step = { q: number; r: number };
const steps = (path: unknown): Step[] => ((path ?? []) as unknown[]).map((s) => (Array.isArray(s) ? { q: s[0] as number, r: s[1] as number } : (s as Step)));

scenario('fire-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = hex(started.villages[0].q, started.villages[0].r);
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const taken = new Set<string>([
    ...started.sites.map((s: { q: number; r: number }) => `${s.q},${s.r}`),
    ...started.camps.map((c: { q: number; r: number }) => `${c.q},${c.r}`),
  ]);
  const cells = [...terrain.keys()].map((k) => k.split(',').map(Number) as [number, number]).map(([q, r]) => hex(q, r));
  const ring = cells.filter((c) => ['plains', 'hills'].includes(terrain.get(`${c.q},${c.r}`)!) && hexDistance(c, home) >= 1 && hexDistance(c, home) <= 2 && !taken.has(`${c.q},${c.r}`));
  const wooded = new Set(ring.map((c) => `${c.q},${c.r}`));
  const burnt = new Set<string>();
  const work = (cell: Hex, action: string) => play({ method: 'POST', path: '/v1/villages/1/terraform', body: { q: cell.q, r: cell.r, action } });
  // Set alight the first wood on a road still ahead (past the next hex).
  const burnOnRoad = async (path: unknown) => {
    const road = steps(path);
    const target = road.slice(2).find((s) => wooded.has(`${s.q},${s.r}`) && !burnt.has(`${s.q},${s.r}`));
    if (!target) return;
    burnt.add(`${target.q},${target.r}`);
    await work(hex(target.q, target.r), 'burn');
  };

  await play({
    set: {
      amounts: { wood: 5000, stone: 5000, grain: 20000, iron: 5000 },
      garrison: { spearman: 20, settler: 3 },
      plots: { c2: { building: 'caravan_yard', level: 1 } },
    },
  });
  for (const c of ring) await work(c, 'plant');
  await play({ advance: 25 * MINUTE });
  await play({ method: 'GET', path: world });

  // A horde on its way: a fire in its road turns it aside.
  hordes: for (let i = 0; i < 200; i++) {
    const seen = (await play({ method: 'GET', path: world })).body;
    for (const wave of (seen?.waves ?? []) as { status: string; path: [number, number, number][] | null; spawnAt: string }[]) {
      if (wave.status !== 'marching' || !wave.path) continue;
      const since = Date.parse(seen.serverTime) - Date.parse(wave.spawnAt);
      const ahead = wave.path.filter((s) => s[2] > since + 2 * MINUTE).map((s) => ({ q: s[0], r: s[1] }));
      if (!ahead.some((s) => wooded.has(`${s.q},${s.r}`))) continue;
      await burnOnRoad([{ q: 0, r: 0 }, { q: 0, r: 0 }, ...ahead]);
      await play({ method: 'GET', path: world });
      break hordes;
    }
    await play({ advance: 2 * MINUTE });
  }
  await play({ advance: 20 * MINUTE });
  await play({ method: 'GET', path: world });

  // An army standing in the wood: no fire there.
  const guard = ring[0]!;
  await play({ set: { garrison: { spearman: 20, settler: 3 } } });
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: guard.q, r: guard.r }, units: { spearman: 2 } } });
  await play({ advance: 5 * MINUTE });
  await work(guard, 'burn');
  burnt.add(`${guard.q},${guard.r}`);

  // An army marching far off and settlers to a new home each find a fire
  // on their road and go round.
  const far = cells
    .filter((c) => hexDistance(c, home) === 5 && terrain.get(`${c.q},${c.r}`) === 'plains' && !taken.has(`${c.q},${c.r}`))
    .sort((a, b) => hexDistance(b, guard) - hexDistance(a, guard));
  const army = (await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: far[1]!.q, r: far[1]!.r }, units: { spearman: 3 } } })).body?.army;
  if (army) await burnOnRoad(army.path);
  const settlers = (await play({ method: 'POST', path: '/v1/villages/1/found', body: { q: far[0]!.q, r: far[0]!.r } })).body?.expedition;
  if (settlers) await burnOnRoad(settlers.path);
  await play({ method: 'GET', path: world });

  // A caravan to the settlers' new village: the fire is set in the very
  // hex it is heading into, so it turns back and goes round.
  for (let i = 0; i < 30; i++) {
    const seen = (await play({ method: 'GET', path: world })).body;
    if ((seen?.villages ?? []).length > 1) break;
    await play({ advance: 2 * MINUTE });
  }
  await play({ set: { amounts: { wood: 5000, stone: 5000, grain: 5000, iron: 5000 } } });
  const caravan = (await play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationVillageId: 2, load: { wood: 100, stone: 0, grain: 0, iron: 0 } } })).body?.caravan;
  for (let i = 0; i < 200 && caravan; i++) {
    await play({ advance: 3000 });
    const seen = (await play({ method: 'GET', path: world })).body;
    const now = seen?.caravans?.find((c: { id: number }) => c.id === caravan.id);
    if (!now || now.status !== 'outbound') break;
    const elapsed = Date.parse(seen.serverTime) - Date.parse(now.departsAt);
    const road = now.path as [number, number, number][];
    const k = road.findIndex((step) => step[2] >= elapsed);
    if (k <= 0) continue;
    const ahead = road[k]!;
    if (!wooded.has(`${ahead[0]},${ahead[1]}`) || burnt.has(`${ahead[0]},${ahead[1]}`) || elapsed <= road[k - 1]![2]) continue;
    burnt.add(`${ahead[0]},${ahead[1]}`);
    await work(hex(ahead[0], ahead[1]), 'burn');
    await play({ method: 'GET', path: world });
    break;
  }
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });
}, 30_000);
