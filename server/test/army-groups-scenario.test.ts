// Army groups in a solo session (data/armies.json groups): refused without
// soldiers, with too many, with no such home and with too long a name; a
// group raised in the home village has its troops trained there at once,
// tagged for it, and once trained they stand there as its army, the second
// batch joining the first; a second group is named after its home and given
// up; out on open ground the army recruits nothing for a bigger
// composition, while in a fort its missing troops are trained in the
// closest village and march out to join it; renamed, and refused a home
// that is no settlement of the player's.
import { hex, hexDistance, hexKey } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 5151, at: '2026-06-01T08:00:00.000Z', name: 'Groups', displayName: 'You', speed: 10, difficulty: 'baron' };

scenario('army-groups-scenario.json', START, async ({ started, play }) => {
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const taken = new Set<string>([
    ...(started.camps as { q: number; r: number }[]).map(hexKey),
    ...(started.sites as { q: number; r: number }[]).map(hexKey),
    ...(started.villages as { q: number; r: number }[]).map(hexKey),
  ]);
  const at = hex(home.q, home.r);
  const open = (distance: number) => {
    for (const [key, t] of terrain) {
      const [q, r] = key.split(',').map(Number) as [number, number];
      if (hexDistance(hex(q, r), at) !== distance || taken.has(key) || t === 'holy_city') continue;
      if (scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost === null) continue;
      if (t === 'plains' || t === 'hills' || t === 'forest') return hex(q, r);
    }
    throw new Error(`No open hex ${distance} out`);
  };
  const field = open(1);
  const fort = open(2);
  const create = (body: object) => play({ method: 'POST', path: '/v1/worlds/-1/army-groups', body });

  await play({
    set: {
      plots: { c2: { building: 'barracks', level: 1 }, c3: { building: 'shooting_range', level: 1 } },
      amounts: { wood: 5000, stone: 5000, grain: 5000, iron: 5000 },
    },
  });
  // Refused.
  await create({ homeVillageId: 1, composition: { settler: 2 } });
  await create({ homeVillageId: 1, composition: { spearman: 2000 } });
  await create({ homeVillageId: 999, composition: { spearman: 1 } });
  await create({ name: 'A name far too long for any army at all', homeVillageId: 1, composition: { spearman: 1 } });
  // Raised: trained at once in the home.
  await create({ name: 'Iron Guard', homeVillageId: 1, composition: { spearman: 4, archer: 2 } });
  await play({ method: 'GET', path: world });
  await play({ advance: 1 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 2 * MINUTE });
  await play({ method: 'GET', path: world });
  // Another, named after its home, given up.
  await create({ homeVillageId: 1, composition: { spearman: 2 } });
  await play({ method: 'POST', path: '/v1/army-groups/2/disband' });
  await play({ advance: 2 * MINUTE });
  await play({ method: 'GET', path: world });

  // On open ground nothing is recruited for a bigger composition.
  await play({ method: 'POST', path: '/v1/armies/1/move', body: { target: field } });
  await play({ method: 'POST', path: '/v1/army-groups/1', body: { composition: { spearman: 6, archer: 2 } } });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });

  // In a fort: trained in the village, they march out to join it.
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q: fort.q, r: fort.r } });
  await play({ advance: 7 * MINUTE });
  await play({ method: 'POST', path: '/v1/armies/1/move', body: { target: fort } });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });

  // Renamed; no home but a settlement of the player's.
  await play({ method: 'POST', path: '/v1/army-groups/1', body: { name: 'Old Guard' } });
  await play({ method: 'POST', path: '/v1/army-groups/1', body: { homeVillageId: 999 } });
  await play({ method: 'GET', path: world });
});
