import { randomInt } from 'node:crypto';
import { insertRivers } from '../db/rivers.js';
import type { Difficulty } from '../data/index.js';
import { ForbiddenError, NotFoundError, RuleError } from '../errors.js';
import type { Account } from '../db/accounts.js';
import { notifyWorld } from '../db/notify.js';
import { inTransaction, type Db, type DbClient } from '../db/pool.js';
import { ensureHeroes } from '../db/heroes.js';
import { ensureDigests, tell } from '../scheduler/notices.js';
import { insertVillage, listVillages } from '../db/villages.js';
import { placeStarterCamps } from '../scheduler/camps.js';
import {
  addMember,
  createWorld,
  findWorldByInviteCode,
  getWorld,
  insertHexes,
  isMember,
  listMembers,
  markAbandoned,
  markLeft,
  markStarted,
  removeMember,
  setClan,
  setHeroKind,
  setHost,
  setQuietHours,
  type Member,
  type World,
} from '../db/worlds.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { announceFirstWaves } from '../scheduler/waves.js';
import { ensureSites } from '../scheduler/sites.js';
import { loadBridge } from '../db/bridges.js';
import { drainWorld, lockWorld, withWorld } from '../scheduler/world.js';
import { refreshBonuses } from '../scheduler/research.js';
import { claimOnboarding } from '../scheduler/onboarding.js';
import { generateMap } from '../sim/mapgen.js';
import { newVillage } from '../sim/village.js';
import { record } from '../db/telemetry.js';
import { townName } from '../sim/names.js';
import { createRng } from '../sim/rng.js';

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
  input: { account: Account; name: string; maxPlayers: number; speed: number; difficulty?: Difficulty },
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
          difficulty: input.difficulty ?? 'normal',
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
    await markStarted(client, world.id, map, input.now, deps.data.horde.holyCity.sanctity);
    await insertHexes(client, world.id, map);
    await insertRivers(client, world.id, map.rivers);
    // Every town gets a name of its own (data/names.json).
    const names: string[] = [];
    const nameRng = createRng((world.seed ^ 0x7a11) >>> 0);
    for (const [i, member] of members.entries()) {
      const site = map.startSites[i]!;
      const name = townName(deps.data, names, nameRng);
      names.push(name);
      await insertVillage(client, {
        worldId: world.id,
        ownerAccountId: member.accountId,
        name,
        q: site.q,
        r: site.r,
        state: newVillage(deps.data, input.now, world.speed),
      });
    }
    await ensureHeroes(client, deps.data, world.id);
    const started = await getWorld(client, world.id);
    // Each village carries its owner's clan.
    await refreshBonuses(client, deps.data, started, members.map((m) => m.accountId), input.now);
    await ensureSites(client, deps.data, started);
    await placeStarterCamps(client, deps.data, started, input.now);
    await loadBridge(client, started.id, input.now, started.sanctity);
    await announceFirstWaves(client, deps.data, started);
    await ensureDigests(client, started, input.now);
    await record(client, world.id, 'run_start', { players: members.length, difficulty: started.difficulty, speed: started.speed, fronts: map.activeFronts }, input.now);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
    return started;
  });
}

// A member picks their clan: freely in the lobby, once a run has started
// only if they have none yet.
export async function setClanCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { account: Account; worldId: number; clan: string; now: Date },
): Promise<void> {
  if (!deps.data.clans.clans[input.clan]) throw new RuleError(`Unknown clan "${input.clan}"`);
  await withWorld(db, input.worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, input.worldId);
    const member = (await listMembers(client, world.id)).find((m) => m.accountId === input.account.id);
    if (!member) throw new ForbiddenError('You are not in this world');
    if (world.status !== 'lobby' && member.clan !== null) throw new RuleError('Your clan is chosen for this run');
    await setClan(client, world.id, input.account.id, input.clan);
    if (world.status === 'running') await refreshBonuses(client, deps.data, world, [input.account.id], input.now);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  });
}

// Each member picks a hero from the roster, one nobody else in the group has.
// It can change in the lobby; once the run starts it is set (members of a run
// from before the roster pick once).
export async function pickHeroCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { account: Account; worldId: number; kind: string; now: Date },
): Promise<void> {
  const def = deps.data.heroes.roster[input.kind];
  if (!def) throw new RuleError(`Unknown hero "${input.kind}"`);
  await withWorld(db, input.worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, input.worldId);
    const members = await listMembers(client, world.id);
    const member = members.find((m) => m.accountId === input.account.id);
    if (!member) throw new ForbiddenError('You are not in this world');
    if (world.status !== 'lobby' && member.heroKind !== null) throw new RuleError('Your hero is chosen for this run');
    if (members.some((m) => m.accountId !== member.accountId && m.heroKind === input.kind)) throw new RuleError(`${def.name} already rides with someone else`);
    await setHeroKind(client, world.id, input.account.id, input.kind);
    if (world.status === 'running') await refreshBonuses(client, deps.data, world, [input.account.id], input.now);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
    await notifyWorld(client, { worldId: world.id, type: 'heroes' });
  });
}

// Claims a getting-started reward from the quest card.
export async function claimOnboardingCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { account: Account; worldId: number; step: string; now: Date },
): Promise<{ villageId: number | null; finale: boolean }> {
  return withWorld(db, input.worldId, input.now, deps, async (client) => {
    const world = await getWorld(client, input.worldId);
    if (world.status !== 'running') throw new RuleError('The run is not under way');
    return claimOnboarding(client, deps.data, world, input.account.id, input.step, input.now);
  });
}

// The host sets when hordes may not arrive (the group's night).
export async function setQuietHoursCommand(
  db: Db,
  input: { account: Account; worldId: number; start: number | null; end: number | null; utcOffsetMinutes: number },
): Promise<void> {
  await inTransaction(db, async (client) => {
    const world = await getWorld(client, input.worldId);
    if (world.hostAccountId !== input.account.id) throw new ForbiddenError('Only the host sets the quiet hours');
    const none = input.start === null || input.end === null || input.start === input.end;
    await setQuietHours(client, world.id, none ? null : { start: input.start!, end: input.end!, utcOffsetMinutes: input.utcOffsetMinutes });
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  });
}

// A player quits a world (they can't or don't want to play any more).
// - In the lobby they are simply gone; if they hosted it, the longest-standing
//   member hosts it now.
// - In a running world their villages go to the teammates who stay, spread
//   evenly, and any hand-over they were part of ends.
// - Quitting a finished world only takes it off their list.
// When nobody is left, the world is abandoned: it stands still and doesn't
// count as a loss.
export async function leaveWorldCommand(
  db: Db,
  deps: SchedulerDeps,
  input: { account: Account; worldId: number; now: Date },
): Promise<void> {
  await inTransaction(db, async (client) => {
    await lockWorld(client, input.worldId);
    let world = await getWorld(client, input.worldId);
    if (world.status === 'running') {
      // Catch up first, so the villages change hands in the present.
      await drainWorld(client, world.id, input.now, deps);
      world = await getWorld(client, world.id);
    }
    const members = await listMembers(client, world.id);
    const me = members.find((m) => m.accountId === input.account.id);
    if (!me) throw new NotFoundError('You are not in this world');
    const others = members.filter((m) => m.accountId !== me.accountId);

    if (world.status === 'lobby') {
      await removeMember(client, world.id, me.accountId);
      if (world.hostAccountId === me.accountId) await setHost(client, world.id, others[0]?.accountId ?? null);
    } else {
      await markLeft(client, world.id, me.accountId, input.now);
    }

    if (world.status === 'running' && others.length > 0) {
      await handOverVillages(client, deps, world, me, others, input.now);
    }
    if (others.length === 0) await markAbandoned(client, world.id, input.now);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  });
}

async function handOverVillages(
  client: DbClient,
  deps: SchedulerDeps,
  world: World,
  leaver: Member,
  stayers: Member[],
  now: Date,
): Promise<void> {
  await client.query(
    'DELETE FROM delegations WHERE world_id = $1 AND (owner_account_id = $2 OR delegate_account_id = $2)',
    [world.id, leaver.accountId],
  );
  const villages = await listVillages(client, world.id);
  const held = new Map(stayers.map((m) => [m.accountId, villages.filter((v) => v.ownerAccountId === m.accountId).length]));
  const given = new Map<number, number>();
  for (const village of villages.filter((v) => v.ownerAccountId === leaver.accountId)) {
    // Whoever holds the fewest takes the next one; ties go to the earliest to join.
    const to = stayers.reduce((best, m) => (held.get(m.accountId)! < held.get(best.accountId)! ? m : best));
    await client.query('UPDATE villages SET owner_account_id = $2 WHERE id = $1', [village.id, to.accountId]);
    held.set(to.accountId, held.get(to.accountId)! + 1);
    given.set(to.accountId, (given.get(to.accountId) ?? 0) + 1);
  }
  // Villages carry their owner's clan and research.
  await refreshBonuses(client, deps.data, world, [...given.keys()], now);
  for (const member of stayers) {
    const count = given.get(member.accountId) ?? 0;
    await tell(client, world, member.accountId, {
      kind: 'member_left',
      tier: 'push',
      title: '{name} left the world',
      body: count === 0 ? 'Their villages went to your teammates.' : count === 1 ? 'You now command one of their villages.' : 'You now command {count} of their villages.',
      vars: { name: leaver.displayName, count },
    }, now);
  }
}
