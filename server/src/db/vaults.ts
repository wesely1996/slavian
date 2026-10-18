import type { Resources } from '../sim/resources.js';
import type { DbClient } from './pool.js';

export interface Vault {
  worldId: number;
  level: number;
  amounts: Resources;
  upgradingTo: number | null;
  upgradeCompletesAt: Date | null;
}

interface VaultRow {
  world_id: number;
  level: number;
  amounts: Resources;
  upgrading_to: number | null;
  upgrade_completes_at: Date | null;
}

// Every world has one; it is created the first time anyone looks.
export async function loadVault(client: DbClient, worldId: number): Promise<Vault> {
  await client.query('INSERT INTO vaults (world_id) VALUES ($1) ON CONFLICT DO NOTHING', [worldId]);
  const { rows } = await client.query<VaultRow>('SELECT * FROM vaults WHERE world_id = $1', [worldId]);
  const row = rows[0]!;
  return {
    worldId: row.world_id,
    level: row.level,
    amounts: row.amounts,
    upgradingTo: row.upgrading_to,
    upgradeCompletesAt: row.upgrade_completes_at,
  };
}

export async function saveVault(client: DbClient, vault: Vault): Promise<void> {
  await client.query(
    `UPDATE vaults SET level = $2, amounts = $3, upgrading_to = $4, upgrade_completes_at = $5 WHERE world_id = $1`,
    [vault.worldId, vault.level, JSON.stringify(vault.amounts), vault.upgradingTo, vault.upgradeCompletesAt],
  );
}
