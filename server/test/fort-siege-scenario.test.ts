// A fort's own defenders and its wall rings in a solo session (forts.json
// garrison, rings): once the first horde is on its way, a fort goes up on
// its road near the village, with a Fort Garrison and its defenders, an
// inner and a middle wall with towers on them, and grain; the horde runs
// into the defenders with no army there, batters the rings one at a time,
// round by round, and the survivors go back into the fort, where the
// Garrison musters the fallen again.
import { hex, hexDistance } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 7373, at: '2026-06-01T08:00:00.000Z', name: 'Siege', displayName: 'You', speed: 10, difficulty: 'baron' };

scenario('fort-siege-scenario.json', START, async ({ started, now, play }) => {
  const world = '/v1/worlds/-1';
  const at = (iso: string) => new Date(iso).getTime();
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };

  // The first horde sets out.
  const first = (await play({ method: 'GET', path: world })).body.waves[0];
  await play({ advance: Math.max(0, at(first.spawnAt) - now().getTime()) + MINUTE });
  const w = (await play({ method: 'GET', path: world })).body;
  const wave = w.waves[0];
  const taken = new Set<string>([...w.camps, ...w.sites, ...w.villages].map((c: { q: number; r: number }) => `${c.q},${c.r}`));
  // A hex on its road within 4 hexes of the village it reaches more than
  // 10 minutes from now (the fort stands within 6).
  const since = now().getTime() - at(wave.spawnAt);
  const step = (wave.path as [number, number, number][]).find(
    ([q, r, ms]) => ms > since + 10 * MINUTE && passable(q, r) && !taken.has(`${q},${r}`) && hexDistance(hex(q, r), hex(home.q, home.r)) <= 4,
  );
  if (!step) throw new Error('No hex on the horde\'s road for a fort');
  const [q, r] = step;
  await play({ set: { amounts: { wood: 9000, stone: 9000, grain: 9000, iron: 9000 } } });
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q, r } });
  await play({ advance: 7 * MINUTE });
  // Its Garrison, walls and towers, and grain.
  await play({
    set: {
      fort: {
        id: 1,
        grain: 2000,
        defenders: { spearman: 4, archer: 4, horseman: 2 },
        plots: {
          keep: { kind: 'keep', level: 4 },
          storage: { kind: 'storage', level: 1 },
          garrison: { kind: 'garrison', level: 2 },
          w0: { kind: 'wall', level: 3 },
          't0-0': { kind: 'archer_tower', level: 2 },
          w1: { kind: 'wall', level: 2 },
          't1-0': { kind: 'ditch', level: 1 },
        },
      },
    },
  });
  // The Garrison raises another level meanwhile.
  await play({ method: 'POST', path: '/v1/forts/1/build', body: { plot: 'garrison', kind: 'garrison' } });
  // The horde reaches the fort and fights its defenders, ring by ring.
  const left = (await play({ method: 'GET', path: world })).body.waves[0];
  const reach = (left.path as [number, number, number][]).find(([pq, pr]) => pq === q && pr === r);
  if (reach) await play({ advance: Math.max(0, at(left.spawnAt) + reach[2] - now().getTime()) + MINUTE });
  await play({ method: 'GET', path: world });
  for (let i = 0; i < 8; i++) {
    await play({ advance: 10 * MINUTE });
    await play({ method: 'GET', path: world });
  }
});
