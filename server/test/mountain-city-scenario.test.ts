// A mountain city in a solo session (events.json mountain_city), as the rare
// daily event would raise it: its mountain hex opens up; the village pays
// the masons (in part, then the rest; a third payment is turned away), and
// spearmen stand guard on the hex while monsters from under the mountain
// strike every few hours, until the city stands and every village produces
// 10% more. A second city, paid for and left unguarded, is overrun and its
// hex is mountain again; a third, never paid for, is given up when the
// event ends. The city that stands trades stone for grain (and nothing
// else) by caravan, and keeps a neutral store of grain a caravan fills and
// the army standing there draws on.
import { loadGameData } from '../src/data/index.js';
import { mountainCitySpot } from '../src/sim/events.js';
import { hex, hexDistance, type Hex } from '../src/sim/hex.js';
import type { TerrainId } from '../src/data/index.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Masons', displayName: 'You', speed: 50, difficulty: 'baron' };
// A game day and hour at speed 50.
const DAY = (24 * 60 * MINUTE) / 50;
const HOUR = DAY / 24;

type View = Record<string, any>;

scenario('mountain-city-scenario.json', START, async ({ started, play }) => {
  const data = loadGameData();
  const world = '/v1/worlds/-1';
  const view = async (): Promise<View> => (await play({ method: 'GET', path: world })).body;
  const home = hex(started.villages[0].q, started.villages[0].r);
  const terrain = new Map<string, TerrainId>((started.map.hexes as [number, number, TerrainId][]).map(([q, r, t]) => [`${q},${r}`, t]));
  // Mountains a city could rise in, nearest the village first, two hexes apart.
  const spots: Hex[] = [];
  for (const cell of [...terrain.keys()]
    .map((k) => hex(...(k.split(',').map(Number) as [number, number])))
    .filter((c) => hexDistance(c, home) <= data.events.kinds.mountain_city.range && mountainCitySpot(data, terrain, c))
    .sort((a, b) => hexDistance(a, home) - hexDistance(b, home) || a.q - b.q || a.r - b.r)) {
    if (spots.every((s) => hexDistance(s, cell) >= 2)) spots.push(cell);
  }
  const [first, second, third] = spots;
  if (!first || !second || !third) throw new Error('not enough mountains near the village');
  const raiders = { grey_wolf: 6, cave_bear: 2 };
  const city = async (at: Hex): Promise<View> => (await view()).shipyards.find((s: View) => s.kind === 'mountain_city' && s.q === at.q && s.r === at.r);

  // The masons wait; the mountain hex opens up.
  await play({ set: { mountainCity: { q: first.q, r: first.r, front: 'north', raiders } } });
  const one = await city(first);
  // What the village has goes in; then (stores filled) the rest, and the
  // city is begun; a third payment is turned away.
  await play({ method: 'POST', path: `/v1/villages/1/shipyards/${one.id}` });
  await play({ set: { amounts: { wood: 3000, stone: 3000, grain: 3000, iron: 3000 } } });
  await play({ method: 'POST', path: `/v1/villages/1/shipyards/${one.id}` });
  await play({ method: 'POST', path: `/v1/villages/1/shipyards/${one.id}` });
  // Spearmen march onto the city's hex and stand guard.
  await play({ set: { garrison: { spearman: 80 } } });
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: first.q, r: first.r }, units: { spearman: 80 } } });
  // Monsters strike every 3 hours until it stands (36 hours).
  for (let i = 0; i < 16; i++) {
    await play({ advance: 3 * HOUR });
    const now = await city(first);
    if (!now || now.status === 'done') break;
  }
  await view();

  // Built: it trades grain for stone (only grain), and keeps a store of
  // grain for armies, filled by caravan; the guard draws on it.
  await play({ set: { plots: { c3: { building: 'caravan_yard', level: 5 } }, amounts: { wood: 1000, stone: 100, grain: 2000, iron: 500 } } });
  const caravan = (load: object, to: object) => play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationVillageId: null, load, ...to } });
  await caravan({ wood: 100, stone: 0, grain: 0, iron: 0 }, { destinationShipyardId: one.id });
  await caravan({ wood: 0, stone: 0, grain: 300, iron: 0 }, { destinationShipyardId: one.id });
  const store = (await view()).forts.find((f: View) => f.neutral);
  if (store) await caravan({ wood: 0, stone: 0, grain: 300, iron: 0 }, { destinationFortId: store.id });
  await play({ advance: 4 * HOUR });
  const guard = (await view()).armies.find((a: View) => a.status === 'stationed');
  if (guard) await play({ method: 'POST', path: `/v1/armies/${guard.id}/resupply` });
  await play({ advance: 4 * HOUR });
  await view();

  // A second city, paid for and left unguarded: overrun, mountain again.
  await play({ set: { mountainCity: { q: second.q, r: second.r, front: 'north', raiders } } });
  const two = await city(second);
  await play({ set: { amounts: { wood: 3000, stone: 3000, grain: 3000, iron: 3000 } } });
  await play({ method: 'POST', path: `/v1/villages/1/shipyards/${two.id}` });
  for (let i = 0; i < 4; i++) {
    await play({ advance: 3 * HOUR });
    await view();
  }

  // A third, never paid for: given up when the event ends.
  await play({ set: { mountainCity: { q: third.q, r: third.r, front: 'north', raiders } } });
  await play({ advance: 2 * DAY + HOUR });
  await view();
  await play({ method: 'GET', path: '/v1/worlds/-1/notifications' });
});
