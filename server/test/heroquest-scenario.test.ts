// Hero quests in a solo session: the hero rides out on a quest of its own
// from home; then it joins an army standing in the field and is offered
// army quests instead: it takes the army on one (the quest's camp or barrow
// rises near the army, which marches on it, storms it and brings the
// reward home) and on a second, which the army is called off from, so its
// place is gone when its time is up.
import { neighbors, hex } from '../src/sim/hex.js';
import { MINUTE, scenario, scheduler } from './scenario.js';

const START = { seed: 5151, at: '2026-06-01T08:00:00.000Z', name: 'Hero quests', displayName: 'You', speed: 10, difficulty: 'normal' };

scenario('heroquest-scenario.json', START, async ({ started, now, play }) => {
  const world = '/v1/worlds/-1';
  const home = started.villages[0] as { q: number; r: number };
  const terrain = new Map<string, string>((started.map.hexes as [number, number, string][]).map(([q, r, t]) => [`${q},${r}`, t]));
  const passable = (q: number, r: number) => {
    const t = terrain.get(`${q},${r}`);
    return t !== undefined && t !== 'holy_city' && scheduler.data.terrain.terrain[t as keyof typeof scheduler.data.terrain.terrain].moveCost !== null;
  };
  const taken = new Set([...(started.camps as { q: number; r: number }[]), ...(started.sites as { q: number; r: number }[])].map((c) => `${c.q},${c.r}`));
  const near = neighbors(hex(home.q, home.r)).filter((n) => passable(n.q, n.r) && !taken.has(`${n.q},${n.r}`));
  type Offer = { id: string; kind: string; army?: boolean };
  const hero = async () => (await play({ method: 'GET', path: world })).body.heroes[0] as { status: string; offers: Offer[]; quest: { returnsAt: string } | null };

  // A quest of its own, from home: one of the new ones if it is offered.
  const offers = (await hero()).offers;
  const own = offers.find((o) => ['hunt', 'tribute', 'shrine'].includes(o.kind)) ?? offers[0]!;
  await play({ method: 'POST', path: '/v1/worlds/-1/hero/quest', body: { offer: own.id } });
  const away = await hero();
  await play({ advance: new Date(away.quest!.returnsAt).getTime() - now().getTime() + MINUTE });
  await play({ method: 'GET', path: world });

  // An army out in the field, strong enough for the quest, with the hero.
  await play({ method: 'POST', path: '/v1/villages/1/build', body: { plot: 'c1', building: 'barracks' } });
  await play({ advance: 30 * MINUTE });
  await play({ set: { garrison: { spearman: 120, archer: 60 } } });
  await play({ method: 'POST', path: '/v1/villages/1/armies', body: { orders: 'hold', target: { q: near[0]!.q, r: near[0]!.r }, units: { spearman: 110, archer: 55 } } });
  await play({ advance: 15 * MINUTE });
  // A quest is no army quest while the hero leads no army.
  await play({ method: 'POST', path: '/v1/worlds/-1/hero/quest', body: { offer: '0:army:warband' } });
  // Back to stand in the village as an army, where the hero joins it.
  await play({ method: 'POST', path: '/v1/armies/1/move', body: { villageId: 1, join: false } });
  await play({ advance: 15 * MINUTE });
  await play({ method: 'POST', path: '/v1/armies/1/hero', body: { join: true } });
  const led = await hero();
  const quest = led.offers.find((o) => o.army && o.kind !== 'barrow') ?? led.offers.find((o) => o.army)!;
  await play({ method: 'POST', path: '/v1/worlds/-1/hero/quest', body: { offer: quest.id } });
  // Only one at a time.
  await play({ method: 'POST', path: '/v1/worlds/-1/hero/quest', body: { offer: led.offers.find((o) => o.army && o.id !== quest.id)?.id ?? quest.id } });
  for (let i = 0; i < 3; i++) {
    await play({ advance: 20 * MINUTE });
    await play({ method: 'GET', path: world });
  }

  // A barrow next, stormed and searched.
  const barrow = (await hero()).offers.find((o) => o.army && o.kind === 'barrow');
  if (barrow) {
    await play({ method: 'POST', path: '/v1/worlds/-1/hero/quest', body: { offer: barrow.id } });
    for (let i = 0; i < 4; i++) {
      await play({ advance: 20 * MINUTE });
      await play({ method: 'GET', path: world });
    }
  }

  // Another one, called off: its place is gone when its time is up.
  const next = (await hero()).offers.find((o) => o.army)!;
  await play({ method: 'POST', path: '/v1/worlds/-1/hero/quest', body: { offer: next.id } });
  await play({ method: 'POST', path: '/v1/armies/1/move', body: { villageId: 1, join: false } });
  await play({ advance: 30 * MINUTE });
  await play({ method: 'GET', path: world });
  await play({ advance: 4 * 60 * MINUTE });
  await play({ method: 'GET', path: world });
});
