import type { HeroSlot, TerrainId } from '../data/index.js';
import { loadLand } from '../db/rivers.js';
import { loadHero, saveHero, type Hero } from '../db/heroes.js';
import { notifyWorld } from '../db/notify.js';
import type { Db, DbClient } from '../db/pool.js';
import { loadVillage } from '../db/villages.js';
import { getWorld, loadHexes, type World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { scheduleEvent, type SchedulerDeps } from '../scheduler/events.js';
import type { HeroPayload } from '../scheduler/heroes.js';
import { withWorld } from '../scheduler/world.js';
import { equip, heroFactor, learnSkill, unequip } from '../sim/heroes.js';
import { hex } from '../sim/hex.js';
import { roadRoute } from '../sim/logistics.js';

interface HeroCommandInput {
  accountId: number;
  worldId: number;
  now: Date;
}

// Runs a change to the caller's hero with the world locked and caught up.
async function heroCommand(
  db: Db,
  deps: SchedulerDeps,
  input: HeroCommandInput,
  apply: (ctx: { client: DbClient; world: World; hero: Hero }) => Promise<Hero>,
): Promise<Hero> {
  return withWorld(db, input.worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, input.worldId);
    const hero = await loadHero(client, world.id, input.accountId);
    const next = await apply({ client, world, hero });
    await saveHero(client, next);
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
    return next;
  });
}

// Sends the hero to another of the caller's villages.
export async function moveHeroCommand(
  db: Db,
  deps: SchedulerDeps,
  input: HeroCommandInput & { villageId: number },
): Promise<Hero> {
  return heroCommand(db, deps, input, async ({ client, world, hero }) => {
    if (hero.status === 'wounded') throw new RuleError(`${hero.name} is wounded`);
    if (hero.status === 'traveling') throw new RuleError(`${hero.name} is already on the road`);
    if (hero.status === 'with_army') throw new RuleError(`${hero.name} is leading an army`);
    if (hero.villageId === input.villageId) throw new RuleError(`${hero.name} is already there`);
    const destination = await loadVillage(client, input.villageId).catch(() => null);
    if (!destination || destination.worldId !== world.id || destination.ownerAccountId !== input.accountId) {
      throw new RuleError('Heroes only travel between your own villages');
    }
    const from = hero.villageId === null ? null : await loadVillage(client, hero.villageId);
    if (!from) throw new RuleError(`${hero.name} has no village to leave from`);
    if (from.state.besieged) throw new RuleError(`${hero.name} won't leave ${from.name} in the middle of a battle`);
    const terrain = await loadLand(client, world.id);
    const path = roadRoute(deps.data, terrain, hex(from.q, from.r), hex(destination.q, destination.r), deps.data.heroes.speed * heroFactor(deps.data, hero.kind, 'heroSpeed'), world.speed);
    const arrivesAt = new Date(input.now.getTime() + path.at(-1)!.atMs);
    const payload: HeroPayload = { accountId: input.accountId };
    await scheduleEvent(client, world.id, arrivesAt, 'hero_arrive', payload);
    return { ...hero, status: 'traveling', villageId: destination.id, path, departsAt: input.now, arrivesAt };
  });
}

export async function learnSkillCommand(db: Db, deps: SchedulerDeps, input: HeroCommandInput & { skill: string }): Promise<Hero> {
  return heroCommand(db, deps, input, async ({ hero }) => ({ ...hero, ...learnSkill(deps.data, hero, input.skill) }));
}

export async function equipCommand(db: Db, deps: SchedulerDeps, input: HeroCommandInput & { item: string }): Promise<Hero> {
  return heroCommand(db, deps, input, async ({ hero }) => ({ ...hero, ...equip(deps.data, hero, input.item) }));
}

export async function unequipCommand(db: Db, deps: SchedulerDeps, input: HeroCommandInput & { slot: HeroSlot }): Promise<Hero> {
  return heroCommand(db, deps, input, async ({ hero }) => ({ ...hero, ...unequip(hero, input.slot) }));
}

export async function renameHeroCommand(db: Db, deps: SchedulerDeps, input: HeroCommandInput & { name: string }): Promise<Hero> {
  return heroCommand(db, deps, input, async ({ hero }) => ({ ...hero, name: input.name }));
}
