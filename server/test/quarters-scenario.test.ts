// Armies apart from their settlements in a solo session: a floor set on the
// village's grain for armies; an army sent to hold a hex next to the village
// and marched back to stand in it as an army (quartered there, not joining
// the garrison); the hero and a general join it and leave it; it splits and
// merges again; its home can't be changed to where it is already; it is
// told not to answer battles, and again to; it stands on a fort with a
// floor of its own, leaves grain there and is fed from it; and when the
// first horde reaches the village, an army standing nearby answers.
import { neighbors, hex } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 4343, at: '2026-06-01T08:00:00.000Z', name: 'Quarters', displayName: 'You', speed: 10, difficulty: 'normal' };

scenario('quarters-scenario.json', START, async ({ started, now, play }) => {
  const at = (iso: string) => new Date(iso).getTime();
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  // Hexes next to the village with no camp or ancient site on them.
  const clear = (w: { camps: { q: number; r: number }[]; sites: { q: number; r: number }[] }) => {
    const taken = new Set([...w.camps, ...w.sites].map((c) => `${c.q},${c.r}`));
    return neighbors(hex(home.q, home.r)).filter((n) => passable(n.q, n.r) && !taken.has(`${n.q},${n.r}`));
  };
  const near = clear(started as never);

  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c1', building: 'heroes_hall' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  // The village keeps 100 grain from armies (by default half its storage).
  await play({ method: 'PUT', path: '/v1/villages/1/army-floor', body: { grain: 100 } });
  await play({ advance: 40 * MINUTE });
  await play({ set: { amounts: { wood: 2000, stone: 2000, grain: 1000, iron: 1000 } } });
  await play({ method: 'POST', path: '/v1/villages/1/generals', body: {} });
  await play({ set: { garrison: { spearman: 12 } } });
  await play({ advance: 10 * MINUTE });

  // Out to the hex next door, and back to stand in the village as an army.
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: near[0]!.q, r: near[0]!.r }, units: { spearman: 8 } } });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'POST', path: '/v1/armies/1/move', body: { villageId: 1, join: false } });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });

  // Its leaders: the hero and the general in the village join it.
  await play({ method: 'POST', path: '/v1/armies/1/hero', body: { join: false } });
  await play({ method: 'POST', path: '/v1/armies/1/hero', body: { join: true } });
  await play({ method: 'POST', path: '/v1/armies/1/hero', body: { join: true } });
  await play({ method: 'POST', path: '/v1/armies/1/general', body: { generalId: 1 } });
  await play({ method: 'POST', path: '/v1/armies/1/general', body: { generalId: 1 } });
  // Split and merged again (two generals never stand in one army).
  await play({ method: 'POST', path: '/v1/armies/1/split', body: { units: { spearman: 8 } } });
  await play({ method: 'POST', path: '/v1/armies/1/split', body: { units: { spearman: 3 }, withGeneral: true } });
  await play({ method: 'POST', path: '/v1/armies/2/merge', body: { armyId: 2 } });
  await play({ method: 'POST', path: '/v1/armies/2/merge', body: { armyId: 1 } });
  await play({ method: 'POST', path: '/v1/armies/2/general', body: { generalId: null } });
  await play({ method: 'POST', path: '/v1/armies/2/hero', body: { join: false } });
  await play({ method: 'GET', path: world });
  // Its home is where it was raised; told not to answer battles, and again to.
  await play({ method: 'POST', path: '/v1/armies/2/home', body: { villageId: 1 } });
  await play({ method: 'POST', path: '/v1/armies/2/respond', body: { respond: false } });
  await play({ method: 'POST', path: '/v1/armies/2/respond', body: { respond: true } });

  // Shortly before the first horde comes, a fort next door, with a floor
  // of its own; the army stands on it (filling up in the village as it
  // sets off), leaves grain there and is fed from it.
  const wave = (await play({ method: 'GET', path: world })).body.waves[0];
  await play({ advance: Math.max(0, at(wave.spawnAt) - now().getTime() - 15 * MINUTE) });
  const fortAt = clear((await play({ method: 'GET', path: world })).body).at(-1)!;
  await play({ set: { amounts: { wood: 2000, stone: 2000, grain: 1000, iron: 1000 } } });
  await play({ method: 'POST', path: '/v1/villages/1/forts', body: { q: fortAt.q, r: fortAt.r } });
  await play({ advance: 8 * MINUTE });
  await play({ method: 'PUT', path: '/v1/forts/1/army-floor', body: { grain: 50 } });
  await play({ method: 'PUT', path: '/v1/forts/1/army-floor', body: { grain: null } });
  await play({ method: 'POST', path: '/v1/armies/2/move', body: { target: { q: fortAt.q, r: fortAt.r } } });
  await play({ advance: 5 * MINUTE });
  await play({ method: 'POST', path: '/v1/armies/2/store', body: { grain: 40 } });
  await play({ advance: 7 * MINUTE });
  await play({ method: 'GET', path: world });

  // When the first horde reaches the village, the army on the fort next
  // door answers, and goes back to the fort once the battle is over.
  const first = (await play({ method: 'GET', path: world })).body.waves[0];
  if (first.arrivesAt) await play({ advance: Math.max(0, at(first.arrivesAt) - now().getTime()) + MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 60 * MINUTE });
  await play({ method: 'GET', path: world });
  // Into the village to join the garrison.
  await play({ method: 'POST', path: '/v1/armies/2/move', body: { villageId: 1 } });
  await play({ advance: 10 * MINUTE });
  await play({ method: 'GET', path: world });
});
