// The enemy lands beyond the edge in a solo session (docs/enemy-lands.md,
// phase 1): an army marches into the North's first band and, once there,
// sees the second (its fog lifts in the world view); a rift between fronts'
// lands takes no army; the army is called home.
import { loadGameData } from '../src/data/index.js';
import { enemyLands } from '../src/sim/enemyLands.js';
import { hex, hexDistance } from '../src/sim/hex.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Beyond the edge', displayName: 'You', speed: 50, difficulty: 'baron' };

scenario('enemy-lands-scenario.json', START, async ({ started, play, now }) => {
  const world = '/v1/worlds/-1';
  const home = hex(started.villages[0].q, started.villages[0].r);
  const enemy = enemyLands(loadGameData(), started.map.enemy.seed, started.map.radius, started.map.activeFronts);
  // The nearest hex of the first band (seen from the start) that an army can stand on.
  const march = enemy
    .filter((e) => e.band === 1 && e.terrain !== 'rift')
    .map((e) => [e.cell.q, e.cell.r] as const)
    .sort((a, b) => hexDistance(hex(a[0], a[1]), home) - hexDistance(hex(b[0], b[1]), home) || a[0] - b[0] || a[1] - b[1])[0]!;
  await play({ set: { garrison: { spearman: 10 } } });
  const sent = await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: march[0], r: march[1] }, units: { spearman: 10 } } });
  if (sent.status !== 200) throw new Error(`army refused: ${JSON.stringify(sent.body)}`);
  const marching = (await play({ method: 'GET', path: world })).body.armies.find((a: { orders: string }) => a.orders === 'hold');
  await play({ advance: new Date(marching.arrivesAt).getTime() - now().getTime() + MINUTE });
  // There: the band past it is seen.
  const after = (await play({ method: 'GET', path: world })).body;
  const army = after.armies.find((a: { orders: string }) => a.orders === 'hold');
  // Rifts keep fronts apart: no army stands there.
  const rift = enemy.find((e) => e.terrain === 'rift');
  if (rift) await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: rift.cell.q, r: rift.cell.r }, units: { spearman: 1 } } });
  if (army) await play({ method: 'POST', path: `/v1/armies/${army.id}/recall`, body: {} });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
});
