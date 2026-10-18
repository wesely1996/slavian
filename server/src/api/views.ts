// JSON shapes sent to clients. Timestamps are ISO strings; clients compute
// current resources from the ledger and their offset to `serverTime`.
import type { DbClient } from '../db/pool.js';
import type { Village } from '../db/villages.js';
import { listVillages } from '../db/villages.js';
import { listMembers, loadHexes, type World } from '../db/worlds.js';

export interface VillageView {
  id: number;
  worldId: number;
  ownerAccountId: number | null;
  name: string;
  q: number;
  r: number;
  levels: Record<string, number>;
  queue: { building: string; targetLevel: number; startsAt: string; completesAt: string }[];
  resources: {
    amounts: Record<string, number>;
    ratesPerHour: Record<string, number>;
    capacity: Record<string, number>;
    settledAt: string;
  };
}

export function villageView(village: Village): VillageView {
  const { levels, queue, ledger } = village.state;
  return {
    id: village.id,
    worldId: village.worldId,
    ownerAccountId: village.ownerAccountId,
    name: village.name,
    q: village.q,
    r: village.r,
    levels: { ...levels },
    queue: queue.map((item) => ({
      building: item.building,
      targetLevel: item.targetLevel,
      startsAt: item.startsAt.toISOString(),
      completesAt: item.completesAt.toISOString(),
    })),
    resources: {
      amounts: ledger.amounts,
      ratesPerHour: ledger.ratesPerHour,
      capacity: ledger.capacity,
      settledAt: ledger.settledAt.toISOString(),
    },
  };
}

export function worldSummary(world: World) {
  return {
    id: world.id,
    name: world.name,
    status: world.status,
    inviteCode: world.inviteCode,
    speed: world.speed,
    maxPlayers: world.maxPlayers,
    hostAccountId: world.hostAccountId,
    startedAt: world.startedAt?.toISOString() ?? null,
  };
}

// Everything a member needs to render the world. Co-op: every member sees
// every village in full.
export async function worldView(client: DbClient, world: World) {
  const [members, villages] = await Promise.all([listMembers(client, world.id), listVillages(client, world.id)]);
  const map =
    world.status === 'lobby'
      ? null
      : { radius: world.radius, activeFronts: world.activeFronts, hexes: await loadHexes(client, world.id) };
  return {
    ...worldSummary(world),
    members: members.map((m) => ({ accountId: m.accountId, displayName: m.displayName })),
    villages: villages.map(villageView),
    map,
  };
}
