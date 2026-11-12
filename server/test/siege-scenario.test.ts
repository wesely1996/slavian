// A siege in a solo session, at a slow world speed so the horde's engines
// take a while: it camps before the walls to build them, and meanwhile the
// archers of both sides shoot (volley rounds, which don't count against
// the battle's length). An army standing nearby answers the battle and
// falls on the horde pinned against the walls (hammer and anvil). Then the
// garrison is ordered out: the walls play no part any more, and the fight
// goes on in the open at once.
import { hex, hexDistance, neighbors } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Siege', displayName: 'You', speed: 10, difficulty: 'normal' };

scenario('siege-scenario.json', START, async ({ started, now, play }) => {
  const at = (iso: string) => new Date(iso).getTime();
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  const rich = { wood: 9000, stone: 9000, grain: 9000, iron: 9000 };

  // No charging out while nobody is at the gates.
  await play({ method: 'POST', path: '/v1/villages/1/sally' });
  await play({ set: { amounts: rich } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { building: 'wall' } });
  await play({ advance: 120 * MINUTE });
  await play({ set: { amounts: rich } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { building: 'wall' } });
  await play({ advance: 240 * MINUTE });
  // The first horde (from the north, which builds no engines) comes and
  // goes; the next, from the south, builds rams. It picks its prey as it
  // sets out: the men come after.
  const first = at((started.waves as { spawnAt: string }[])[0]!.spawnAt);
  await play({ advance: Math.max(MINUTE, first - now().getTime() + 6 * 60 * MINUTE) });
  const next = (await play({ method: 'GET', path: world })).body.waves.find((w: { status: string }) => w.status === 'scheduled');
  const spawnAt = at(next.spawnAt);
  await play({ advance: Math.max(MINUTE, spawnAt - now().getTime() + MINUTE) });
  await play({ set: { garrison: { archer: 6, spearman: 14 } } });
  const before = (await play({ method: 'GET', path: world })).body;
  const marching = (before.waves as { id: number; status: string; path?: [number, number, number][]; arrivesAt?: string }[]).find((w) => w.status === 'marching') ?? before.waves[0];

  // An army stands two hexes off, away from the horde's road: it answers
  // the battle when it starts.
  const road = new Set<string>(((marching.path ?? []) as [number, number, number][]).map(([q, r]) => `${q},${r}`));
  const ring = neighbors(hex(home.q, home.r)).flatMap((n) => neighbors(n)).filter((n) => hexDistance(n, hex(home.q, home.r)) === 2 && passable(n.q, n.r));
  const post = ring.find((n) => !road.has(`${n.q},${n.r}`)) ?? ring[0]!;
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: post.q, r: post.r }, units: { spearman: 6 } } });

  // The horde arrives; round by round (ten real minutes each).
  const arrives = marching.arrivesAt ? at(marching.arrivesAt) : spawnAt + 60 * MINUTE;
  await play({ advance: Math.max(MINUTE, arrives - now().getTime() + 1_000) });
  await play({ method: 'GET', path: world });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });
  // Out of the gates: once, and not twice.
  await play({ method: 'POST', path: '/v1/villages/1/sally' });
  await play({ method: 'POST', path: '/v1/villages/1/sally' });
  for (let i = 0; i < 4; i++) {
    await play({ advance: 10 * MINUTE });
    await play({ method: 'GET', path: world });
  }
});
