// Army groups (migration 090; scheduler/armyGroups.ts): a named army with
// a set composition and a home settlement where it gathers.
import { NotFoundError } from '../errors.js';
import type { DbClient } from './pool.js';

export interface ArmyGroup {
  id: number;
  worldId: number;
  ownerAccountId: number;
  name: string;
  // The troops it should hold, by unit.
  composition: Record<string, number>;
  homeVillageId: number;
  // The army it fields (null: none standing yet).
  armyId: number | null;
  createdAt: Date;
}

interface ArmyGroupRow {
  id: number | string;
  world_id: number | string;
  owner_account_id: number | string;
  name: string;
  composition: Record<string, number>;
  home_village_id: number | string;
  army_id: number | string | null;
  created_at: Date;
}

function fromRow(row: ArmyGroupRow): ArmyGroup {
  return {
    id: Number(row.id),
    worldId: Number(row.world_id),
    ownerAccountId: Number(row.owner_account_id),
    name: row.name,
    composition: row.composition,
    homeVillageId: Number(row.home_village_id),
    armyId: row.army_id === null ? null : Number(row.army_id),
    createdAt: row.created_at,
  };
}

export async function insertArmyGroup(client: DbClient, g: Omit<ArmyGroup, 'id' | 'armyId'>): Promise<ArmyGroup> {
  const { rows } = await client.query<ArmyGroupRow>(
    `INSERT INTO army_groups (world_id, owner_account_id, name, composition, home_village_id, created_at)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
    [g.worldId, g.ownerAccountId, g.name, JSON.stringify(g.composition), g.homeVillageId, g.createdAt],
  );
  return fromRow(rows[0]!);
}

export async function loadArmyGroup(client: DbClient, id: number): Promise<ArmyGroup> {
  const { rows } = await client.query<ArmyGroupRow>('SELECT * FROM army_groups WHERE id = $1', [id]);
  if (!rows[0]) throw new NotFoundError(`Army group ${id} not found`);
  return fromRow(rows[0]);
}

export async function findArmyGroup(client: DbClient, id: number): Promise<ArmyGroup | null> {
  const { rows } = await client.query<ArmyGroupRow>('SELECT * FROM army_groups WHERE id = $1', [id]);
  return rows[0] ? fromRow(rows[0]) : null;
}

export async function listArmyGroups(client: DbClient, worldId: number, ownerAccountId?: number): Promise<ArmyGroup[]> {
  const { rows } = ownerAccountId === undefined
    ? await client.query<ArmyGroupRow>('SELECT * FROM army_groups WHERE world_id = $1 ORDER BY id', [worldId])
    : await client.query<ArmyGroupRow>('SELECT * FROM army_groups WHERE world_id = $1 AND owner_account_id = $2 ORDER BY id', [worldId, ownerAccountId]);
  return rows.map(fromRow);
}

export async function saveArmyGroup(client: DbClient, g: ArmyGroup): Promise<void> {
  await client.query('UPDATE army_groups SET name = $2, composition = $3, home_village_id = $4, army_id = $5 WHERE id = $1', [
    g.id,
    g.name,
    JSON.stringify(g.composition),
    g.homeVillageId,
    g.armyId,
  ]);
}

export async function deleteArmyGroup(client: DbClient, id: number): Promise<void> {
  await client.query('UPDATE armies SET group_id = NULL WHERE group_id = $1', [id]);
  await client.query('DELETE FROM army_groups WHERE id = $1', [id]);
}

// An army marching to join a group carries its id (null: none).
export async function setArmyGroupTag(client: DbClient, armyId: number, groupId: number | null): Promise<void> {
  await client.query('UPDATE armies SET group_id = $2 WHERE id = $1', [armyId, groupId]);
}
