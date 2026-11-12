// A shipyard in a solo session: a daily event on a river bank the village
// pays for over a few days; while the boat is built, raiders strike and an
// army standing there fights them (or work is lost); once it is done, an
// army marching along the river goes three times as fast.
import { hex, hexDistance } from '../src/sim/hex.js';
import { riverLanes } from '../src/sim/land.js';
import { MINUTE, scenario } from './scenario.js';

const START = { seed: 4242, at: '2026-06-01T08:00:00.000Z', name: 'Shipyard', displayName: 'You', speed: 50, difficulty: 'normal' };
// A game day at speed 50.
const DAY = (24 * 60 * MINUTE) / 50;
const HOUR = DAY / 24;

type View = Record<string, any>;

scenario('shipyard-scenario.json', START, async ({ play }) => {
  const world = '/v1/worlds/-1';
  const view = async (): Promise<View> => (await play({ method: 'GET', path: world })).body;
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c2', building: 'barracks' } });
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c3', building: 'caravan_yard' } });
  await play({ advance: 20 * MINUTE });
  await play({ method: 'POST', path: '/v1/villages/1/train', body: { unit: 'spearman', count: 6 } });
  await play({ advance: 15 * MINUTE });

  // Days go by until boatwrights wait somewhere. The first day, a caravan
  // takes them part of what they need (more than they need is refused);
  // after that the village sends what it can each day until the boat is
  // paid for, and the spearmen go to stand guard (they are there before
  // the first raiders).
  let shipyard: View | undefined;
  let caravan = false;
  for (let day = 1; day <= 12; day++) {
    await play({ advance: DAY });
    shipyard = (await view()).shipyards.find((s: View) => s.status !== 'done');
    if (shipyard && !caravan) {
      caravan = true;
      const send = (load: object) => play({ method: 'POST', path: '/v1/villages/1/caravans', body: { destinationShipyardId: shipyard!.id, load } });
      await send({ wood: 0, stone: 0, grain: 0, iron: 151 });
      await send({ wood: 200, stone: 100, grain: 0, iron: 0 });
      await play({ advance: 2 * HOUR });
      await view();
    } else if (shipyard) {
      await play({ method: 'POST', path: `/v1/villages/1/shipyards/${shipyard.id}` });
      shipyard = (await view()).shipyards.find((s: View) => s.id === shipyard!.id);
      if (shipyard?.status === 'building') break;
    }
  }
  if (!shipyard || shipyard.status !== 'building') throw new Error('no shipyard was begun');
  // A second payment is turned away: it is paid for.
  await play({ method: 'POST', path: `/v1/villages/1/shipyards/${shipyard.id}` });

  // A strong guard (the raiders come every 2 hours, and burned 3 times the
  // boat would be lost).
  await play({ set: { garrison: { spearman: 40 } } });
  const spearmen = (await view()).villages[0].garrison.spearman ?? 0;
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: shipyard.q, r: shipyard.r }, units: { spearman: spearmen } } });

  // Raids come every 2 hours until the boat is done: the spearmen stand
  // guard and drive them off.
  for (let i = 0; i < 16; i++) {
    await play({ advance: 2 * HOUR });
    const now = (await view()).shipyards.find((s: View) => s.id === shipyard!.id);
    if (!now || now.status === 'done') break;
  }
  const done = (await view()).shipyards.find((s: View) => s.id === shipyard!.id);
  if (done && done.status !== 'done') await play({ advance: 2 * DAY });

  // Along the river now: the army still standing there (or what is left of
  // it, sent out again) marches down it, to the bank hex furthest from the
  // shipyard (up to 6 hexes off).
  let state = await view();
  let army = state.armies.find((a: View) => a.status === 'stationed');
  const left = state.villages[0].garrison.spearman ?? 0;
  if (!army && left > 0) {
    await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: shipyard.q, r: shipyard.r }, units: { spearman: left } } });
    await play({ advance: 4 * HOUR });
    state = await view();
    army = state.armies.find((a: View) => a.status === 'stationed');
  }
  if (army) {
    const rivers = state.map.rivers.map(([aq, ar, bq, br]: number[]) => ({ a: hex(aq!, ar!), b: hex(bq!, br!) }));
    const [aq, ar, bq, br] = done.edge;
    const banks = new Set(riverLanes(rivers, { a: hex(aq, ar), b: hex(bq, br) }).flatMap((k) => k.split('|')));
    const here = hex(shipyard.q, shipyard.r);
    const far = [...banks]
      .map((k) => hex(...(k.split(',').map(Number) as [number, number])))
      .filter((h) => hexDistance(h, here) <= 6)
      .sort((x, y) => hexDistance(y, here) - hexDistance(x, here) || x.q - y.q || x.r - y.r)[0]!;
    await play({ method: 'POST', path: `/v1/armies/${army.id}/move`, body: { target: far } });
  }
  await play({ advance: 4 * HOUR });
  await view();

  // Another shipyard, paid for and left unguarded: burned 3 times, it is lost.
  const other = (await view()).shipyards.find((s: View) => s.status === 'open');
  if (other) {
    await play({ set: { amounts: { wood: 3000, stone: 3000, grain: 3000, iron: 3000 } } });
    await play({ method: 'POST', path: `/v1/villages/1/shipyards/${other.id}` });
    for (let i = 0; i < 4; i++) {
      await play({ advance: 2 * HOUR });
      await view();
    }
  }
});
