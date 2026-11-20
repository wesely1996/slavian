// A player's army slots (sim/slots.ts): used and given.
import type { GameData } from '../data/index.js';
import { listArmies } from '../db/armies.js';
import { listCaravans } from '../db/caravans.js';
import type { DbClient } from '../db/pool.js';
import { listVillages } from '../db/villages.js';
import { slotCap, slotsUsed } from '../sim/slots.js';

export async function armySlotsOf(client: DbClient, data: GameData, worldId: number, accountId: number): Promise<{ used: number; cap: number }> {
  const villages = (await listVillages(client, worldId)).filter((v) => v.ownerAccountId === accountId);
  const armies = (await listArmies(client, worldId)).filter((a) => a.ownerAccountId === accountId);
  const ids = new Set(villages.map((v) => v.id));
  const caravans = (await listCaravans(client, worldId)).filter((c) => ids.has(c.villageId));
  return { used: slotsUsed(data, { villages, armies, caravans }), cap: slotCap(data, villages) };
}
