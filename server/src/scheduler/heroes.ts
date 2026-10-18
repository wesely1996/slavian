// Heroes on the scheduler: hero_arrive ends a journey, hero_recover ends
// a wound. Battles (battles.ts) give XP, gear and wounds.
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { loadHero, saveHero, type Hero } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import type { World } from '../db/worlds.js';
import { gainXp, rollDrop, woundMs } from '../sim/heroes.js';
import { tell } from './notices.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

export const heroPayload = z.object({ accountId: z.number().int() });
export type HeroPayload = z.infer<typeof heroPayload>;

// After a battle the hero fought in: XP for the enemies that fell, maybe
// gear from a beaten horde, or a wound when the village fell.
export async function heroAfterBattle(
  client: DbClient,
  data: GameData,
  world: World,
  hero: Hero,
  result: { kills: number; won: boolean; battleId: number; at: Date },
): Promise<void> {
  let next: Hero = { ...hero, ...gainXp(data, hero, result.kills) };
  if (result.won) {
    const item = rollDrop(data, next, world.seed, result.battleId);
    if (item) next = { ...next, inventory: [...next.inventory, item] };
  } else {
    const woundedUntil = new Date(result.at.getTime() + woundMs(data, world.speed));
    next = { ...next, status: 'wounded', woundedUntil };
    const payload: HeroPayload = { accountId: hero.accountId };
    await scheduleEvent(client, world.id, woundedUntil, 'hero_recover', payload);
  }
  await saveHero(client, next);
  await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  if (!result.won) {
    await tell(client, world, hero.accountId, { kind: 'hero', tier: 'digest', title: `${hero.name} is wounded`, body: 'Back on their feet in a few hours.' }, result.at);
  } else if (next.level > hero.level) {
    await tell(client, world, hero.accountId, { kind: 'hero', tier: 'digest', title: `${hero.name} reached level ${next.level}`, body: 'A new skill point to spend.' }, result.at);
  }
}

export const heroHandlers: HandlerRegistry = {
  async hero_arrive({ client, world }, event) {
    const hero = await loadHero(client, world.id, heroPayload.parse(event.payload).accountId);
    if (hero.status !== 'traveling' || !hero.arrivesAt || hero.arrivesAt > event.dueAt) return;
    await saveHero(client, { ...hero, status: 'home', path: null, departsAt: null, arrivesAt: null });
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  },

  async hero_recover({ client, world }, event) {
    const hero = await loadHero(client, world.id, heroPayload.parse(event.payload).accountId);
    if (hero.status !== 'wounded' || !hero.woundedUntil || hero.woundedUntil > event.dueAt) return;
    await saveHero(client, { ...hero, status: 'home', woundedUntil: null });
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  },
};
