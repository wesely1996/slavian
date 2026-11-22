// Forts as strongholds in a solo session (forts.json): a fort two hexes
// out starts with its Keep and Storage; the Keep rises a level, the inner
// wall goes up and an archer tower on it, while the middle wall waits for
// the Keep and a tower may not rise above its wall; a supply point and an
// outpost share its hex; the village reshapes the land and builds a road in
// the fort's zone, beyond its own reach; the fort is the rally point, and
// newly trained troops march there to hold it; it eats the grain an army
// left there; the supply point is torn down; and once its grain is gone and
// no army holds it, bandits take the fort.
import { hex, hexDistance, hexKey, neighbors } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const HOUR = 60 * MINUTE;

const START = { seed: 5151, at: '2026-06-01T08:00:00.000Z', name: 'Stronghold', displayName: 'You', speed: 10, difficulty: 'baron' };

scenario('fort-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const land = (c: { q: number; r: number }) => terrain.get(hexKey(c));
  const passable = (c: { q: number; r: number }) => {
    const t = land(c);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  const taken = new Set<string>([
    ...(started.camps as { q: number; r: number }[]).map(hexKey),
    ...(started.sites as { q: number; r: number }[]).map(hexKey),
    ...(started.villages as { q: number; r: number }[]).map(hexKey),
  ]);
  const at = hex(home.q, home.r);
  // A fort 2 hexes out with a plain or a hill beside it 3 hexes out: beyond
  // the village's reach for reshaping (field.json terraform range 2),
  // within the fort's zone.
  const plantable = (c: { q: number; r: number }) => ['plains', 'hills'].includes(land(c) ?? '') && !taken.has(hexKey(c));
  let fort: { q: number; r: number } | null = null;
  let field: { q: number; r: number } | null = null;
  for (const [key] of terrain) {
    const [q, r] = key.split(',').map(Number) as [number, number];
    const c = hex(q, r);
    if (hexDistance(c, at) !== 2 || !passable(c) || taken.has(key)) continue;
    const beside = neighbors(c).find((n) => hexDistance(n, at) >= 3 && plantable(n));
    if (beside) {
      fort = c;
      field = beside;
      break;
    }
  }
  if (!fort || !field) throw new Error('No place for the fort');

  await play({ set: { plots: { c2: { building: 'barracks', level: 1 } }, amounts: { wood: 5000, stone: 5000, grain: 5000, iron: 5000 } } });
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q: fort.q, r: fort.r } });
  // Nothing rises in it until it stands.
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 'keep', kind: 'keep' } });
  await play({ advance: 7 * MINUTE });
  await play({ method: 'GET', path: world });

  // Its buildings.
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 'keep', kind: 'keep' } });
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 'w0', kind: 'wall' } });
  await play({ advance: 3 * MINUTE });
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 'w0', kind: 'wall' } });
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 'w1', kind: 'wall' } });
  await play({ advance: MINUTE });
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 't0-0', kind: 'archer_tower' } });
  await play({ advance: MINUTE });
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 't0-0', kind: 'archer_tower' } });
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 't0-1', kind: 'archer_tower' } });
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 'keep', kind: 'wall' } });
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 'storage', kind: 'storage' } });
  await play({ advance: 2 * MINUTE });
  // The middle wall waits for the Keep at level 4.
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 'w1', kind: 'wall' } });
  await play({ method: 'GET', path: world });

  // A supply point and an outpost on the same hex; not a second fort.
  await play({ set: { amounts: { wood: 5000, stone: 5000, grain: 5000, iron: 5000 } } });
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q: fort.q, r: fort.r } });
  await play({ method: 'POST', path: '/v1/villages/1/supply-points', body: { q: fort.q, r: fort.r } });
  await play({ method: 'POST', path: '/v1/villages/1/outposts', body: { q: fort.q, r: fort.r } });
  // Reshaping and a road in its zone, beyond the village's reach.
  await play({ method: 'POST', path: '/v1/villages/1/terraform', body: { q: field.q, r: field.r, action: 'plant' } });
  await play({ method: 'POST', path: '/v1/villages/1/roads', body: { a: { q: fort.q, r: fort.r }, b: { q: field.q, r: field.r } } });
  await play({ advance: 5 * MINUTE });

  // The fort is the rally point: newly trained spearmen march there.
  await play({ method: 'PUT', path: `${world}/rally`, body: { villageId: null, fortId: 2 } });
  await play({ method: 'PUT', path: `${world}/rally`, body: { villageId: null, fortId: 1 } });
  await play({ set: { amounts: { wood: 5000, stone: 5000, grain: 5000, iron: 5000 } } });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 4 } });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
  // The army there leaves grain; the fort eats it while the army holds it.
  const army = ((await play({ method: 'GET', path: world })).body.armies as { id: number; status: string }[]).find((a) => a.status === 'stationed');
  if (army) {
    await play({ method: 'POST', path: `/v1/armies/${army.id}/store`, body: { grain: 100 } });
    await play({ method: 'GET', path: world });
    await play({ advance: 30 * MINUTE });
    await play({ method: 'GET', path: world });
    await play({ method: 'POST', path: `/v1/armies/${army.id}/recall` });
  }
  // The supply point is torn down.
  await play({ method: 'DELETE', path: '/v1/forts/2' });
  await play({ method: 'DELETE', path: '/v1/forts/2' });
  await play({ advance: 3 * HOUR });
  await play({ method: 'GET', path: world });
  // Unfed and empty: bandits take it.
  await play({ advance: 2 * HOUR });
  await play({ method: 'GET', path: world });
});
