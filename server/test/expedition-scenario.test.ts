// Expeditions in a solo session: armies out in the field set out from where
// they stand. One holding a hex near the village is refused for a side no
// enemy comes from and while still in the village, then raids the South a
// field deep and comes home with its loot; another storms a bandit camp from
// the field, and its spoils go straight home while it stays out; and a third
// strikes a horde still gathering beyond the edge.
import { hex, neighbors } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Expeditions', displayName: 'You', speed: 50, difficulty: 'baron' };
// A game hour at speed 50.
const HOUR = (60 * MINUTE) / 50;

scenario('expedition-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (c: { q: number; r: number }) => {
    const t = terrain.get(`${c.q},${c.r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  const taken = new Set<string>([...(started.camps as { q: number; r: number }[]), ...(started.sites as { q: number; r: number }[])].map((c) => `${c.q},${c.r}`));
  const near = neighbors(hex(home.q, home.r)).filter((n) => passable(n) && !taken.has(`${n.q},${n.r}`));
  type ArmyView = { id: number; status: string; orders: string; units: Record<string, number>; loot: Record<string, number> | null };
  const armies = async () => (await play({ method: 'GET', path: world })).body.armies as ArmyView[];

  await play({ set: { garrison: { spearman: 40 } } });
  // Out to hold two hexes beside the village.
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: near[0]!.q, r: near[0]!.r }, units: { spearman: 14 } } });
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: near[1]!.q, r: near[1]!.r }, units: { spearman: 14 } } });
  // Not yet there: refused.
  await play({ method: 'POST', path: '/v1/armies/1/raid', body: { front: 'south', depth: 1 } });
  await play({ advance: 10 * MINUTE });
  // A side no enemy comes from, too deep, and an army that isn't there.
  await play({ method: 'POST', path: '/v1/armies/1/raid', body: { front: 'east', depth: 1 } });
  await play({ method: 'POST', path: '/v1/armies/1/raid', body: { front: 'south', depth: 9 } });
  await play({ method: 'POST', path: '/v1/armies/99/raid', body: { front: 'south', depth: 1 } });
  // Off to raid the South from where it stands.
  await play({ method: 'POST', path: '/v1/armies/1/raid', body: { front: 'south', depth: 1 } });
  await play({ method: 'POST', path: '/v1/armies/1/raid', body: { front: 'south', depth: 1 } });
  await play({ method: 'GET', path: world });

  // The second storms the starter camp from the field: its spoils go home.
  const camp = (started.camps as { q: number; r: number }[])[0];
  if (camp) {
    await play({ method: 'POST', path: '/v1/armies/2/move', body: { target: { q: camp.q, r: camp.r } } });
    await play({ advance: 20 * MINUTE });
    await play({ method: 'GET', path: world });
  }

  // A strike on the first horde while it still gathers.
  const wave = (await play({ method: 'GET', path: world })).body.waves.find((w: { status: string }) => w.status === 'scheduled');
  await play({ method: 'POST', path: '/v1/armies/2/strike', body: { waveId: 999 } });
  if (wave) await play({ method: 'POST', path: '/v1/armies/2/strike', body: { waveId: wave.id } });

  // Through the stages and home.
  for (let i = 0; i < 6; i++) {
    await play({ advance: 2 * HOUR });
    await armies();
  }
  await play({ advance: 12 * HOUR });
  await play({ method: 'GET', path: world });
});
