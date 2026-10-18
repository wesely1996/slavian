import { randomInt } from 'node:crypto';
import { ForbiddenError, NotFoundError, RuleError } from '../errors.js';
import type { Account } from '../db/accounts.js';
import { notifyWorld } from '../db/notify.js';
import { inTransaction, type Db } from '../db/pool.js';
import { insertVillage } from '../db/villages.js';
import {
  addMember,
  createWorld,
  findWorldByInviteCode,
  getWorld,
  insertHexes,
  isMember,
  listMembers,
  markStarted,
  type World,
} from '../db/worlds.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { lockWorld } from '../scheduler/world.js';
import { generateMap } from '../sim/mapgen.js';
import { newVillage } from '../sim/village.js';

// No 0/O, 1/I/L: invite codes get read aloud and typed on phones.
const INVITE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const INVITE_LENGTH = 6;
const UNIQUE_VIOLATION = '23505';

export function newInviteCode(): string {
  return Array.from({ length: INVITE_LENGTH }, () => INVITE_ALPHABET[randomInt(INVITE_ALPHABET.length)]).join('');
}

export function normalizeInviteCode(code: string): string {
  return code.trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
}

export async function createWorldCommand(
  db: Db,
  input: { account: Account; name: string; maxPlayers: number; speed: number },
): Promise<World> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await inTransaction(db, async (client) => {
        const world = await createWorld(client, {
          name: input.name,
          seed: randomInt(2 ** 31),
          speed: input.speed,
          hostAccountId: input.account.id,
          maxPlayers: input.maxPlayers,
          inviteCode: newInviteCode(),
        });
        await addMember(client, world.id, input.account.id);
        return world;
      });
    } catch (error) {
      // Invite code collision: try another code.
      if ((error as { code?: string }).code !== UNIQUE_VIOLATION || attempt >= 5) throw error;
    }
  }
}

export async function joinWorldCommand(db: Db, input: { account: Account; inviteCode: string }): Promise<World> {
  return inTransaction(db, async (client) => {
    const found = await findWorldByInviteCode(client, normalizeInviteCode(input.inviteCode));
    if (!found) throw new NotFoundError('No world with that invite code');
    await lockWorld(client, found.id);
    const world = await getWorld(client, found.id);
    if (await isMember(client, world.id, input.account.id)) return world;
    if (world.status !== 'lobby') throw new RuleError('This world has already started');
    const members = await listMembers(client, world.id);
    if (members.length >= world.maxPlayers) throw new RuleError('This world is full');
    await addMember(client, world.id, input.account.id);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
    return world;
  });
}

// Generates the map for the actual number of players and founds a village
// for each of them on the starting ring.
export async function startWorldCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { account: Account; worldId: number; now: Date },
): Promise<World> {
  return inTransaction(db, async (client) => {
    await lockWorld(client, input.worldId);
    const world = await getWorld(client, input.worldId);
    if (world.hostAccountId !== input.account.id) throw new ForbiddenError('Only the host can start the world');
    if (world.status !== 'lobby') throw new RuleError('This world has already started');

    const members = await listMembers(client, world.id);
    const map = generateMap(deps.data, world.seed, members.length);
    await markStarted(client, world.id, map, input.now);
    await insertHexes(client, world.id, map);
    for (const [i, member] of members.entries()) {
      const site = map.startSites[i]!;
      await insertVillage(client, {
        worldId: world.id,
        ownerAccountId: member.accountId,
        name: `${member.displayName}'s village`,
        q: site.q,
        r: site.r,
        state: newVillage(deps.data, input.now, world.speed),
      });
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
    return getWorld(client, world.id);
  });
}
