// Generals on the scheduler: general_ready ends a recruitment,
// general_arrive a journey. Battles give XP, or kill a general whose side
// lost (generalAfterBattle).
import { z } from 'zod';
import type { GameData } from '../data/index.js';
import { deleteGeneral, loadGeneral, saveGeneral, type General } from '../db/generals.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { loadVillage } from '../db/villages.js';
import type { World } from '../db/worlds.js';
import { generalGainXp } from '../sim/generals.js';
import { tell } from './notices.js';
import type { HandlerRegistry } from './events.js';

export const generalPayload = z.object({ generalId: z.number().int() });
export type GeneralPayload = z.infer<typeof generalPayload>;

// The level of the Hero's Hall in a village (0: none, or no village).
export async function hallLevelAt(client: DbClient, villageId: number | null): Promise<number> {
  if (villageId === null) return 0;
  const village = await loadVillage(client, villageId).catch(() => null);
  return village?.state.levels.heroes_hall ?? 0;
}

// A general falls: it is gone (armies it led forget it).
export async function killGeneral(client: DbClient, world: World, general: General, at: Date): Promise<void> {
  await deleteGeneral(client, general.id);
  await notifyWorld(client, { worldId: world.id, type: 'generals' });
  await tell(client, world, general.accountId, { kind: 'hero', tier: 'digest', title: '{name} fell in battle', body: 'Recruit another at a Hero\'s Hall.', vars: { name: general.name } }, at);
}

// After a battle a general fought in: XP for the enemies that fell, or
// death when its side lost.
export async function generalAfterBattle(
  client: DbClient,
  data: GameData,
  world: World,
  general: General,
  result: { kills: number; won: boolean; at: Date },
): Promise<void> {
  if (!result.won) {
    await killGeneral(client, world, general, result.at);
    return;
  }
  const next = generalGainXp(data, general, result.kills);
  await saveGeneral(client, next);
  await notifyWorld(client, { worldId: world.id, type: 'generals' });
  if (next.level > general.level) {
    await tell(client, world, general.accountId, { kind: 'hero', tier: 'digest', title: '{name} reached level {level}', body: 'The troops they lead fight a little harder.', vars: { name: general.name, level: next.level } }, result.at);
  }
}

export const generalHandlers: HandlerRegistry = {
  async general_ready({ client, world }, event) {
    const general = await loadGeneral(client, generalPayload.parse(event.payload).generalId).catch(() => null);
    if (!general || general.status !== 'recruiting' || !general.until || general.until > event.dueAt) return;
    await saveGeneral(client, { ...general, status: 'home', until: null });
    await notifyWorld(client, { worldId: world.id, type: 'generals' });
    await tell(client, world, general.accountId, { kind: 'hero', tier: 'digest', title: '{name} answers your call', body: 'A new general stands ready.', vars: { name: general.name } }, event.dueAt);
  },

  async general_arrive({ client, world }, event) {
    const general = await loadGeneral(client, generalPayload.parse(event.payload).generalId).catch(() => null);
    if (!general || general.status !== 'traveling' || !general.until || general.until > event.dueAt) return;
    await saveGeneral(client, { ...general, status: 'home', path: null, departsAt: null, until: null });
    await notifyWorld(client, { worldId: world.id, type: 'generals' });
  },
};
