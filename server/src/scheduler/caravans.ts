// Caravans on the scheduler: caravan_arrive unloads (or loads, when
// fetching from the vault) at the far end; caravan_return brings home
// whatever the caravan carries back. vault_upgrade finishes a vault level.
import { z } from 'zod';
import { loadCaravan, markCaravanDone, markReturning } from '../db/caravans.js';
import { notifyWorld } from '../db/notify.js';
import { loadVault, saveVault } from '../db/vaults.js';
import { loadVillage, saveVillageState } from '../db/villages.js';
import { receive, store, total, vaultCapacity, withdraw } from '../sim/logistics.js';
import { emptyResources } from '../sim/resources.js';
import { tell } from './notices.js';
import { planAmbushes } from './camps.js';
import { returnHome } from '../sim/village.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';

export const caravanPayload = z.object({ caravanId: z.number().int() });
export type CaravanPayload = z.infer<typeof caravanPayload>;

export const caravanHandlers: HandlerRegistry = {
  async caravan_arrive({ client, data, world }, event) {
    const caravan = await loadCaravan(client, caravanPayload.parse(event.payload).caravanId);
    if (caravan.status !== 'outbound') return;
    let carriedBack = emptyResources();
    if (caravan.destinationVillageId === null) {
      const vault = await loadVault(client, world.id);
      if (caravan.kind === 'deliver') {
        const stored = store(vault.amounts, vaultCapacity(data, vault.level), caravan.cargo);
        await saveVault(client, { ...vault, amounts: stored.amounts });
        carriedBack = stored.leftover;
      } else {
        const taken = withdraw(vault.amounts, caravan.cargo);
        await saveVault(client, { ...vault, amounts: taken.amounts });
        carriedBack = taken.taken;
      }
    } else {
      const village = await loadVillage(client, caravan.destinationVillageId);
      const received = receive(village.state.ledger, event.dueAt, caravan.cargo);
      await saveVillageState(client, village.id, { ...village.state, ledger: received.ledger });
      await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
      carriedBack = received.leftover;
      const sender = await loadVillage(client, caravan.villageId);
      if (sender.ownerAccountId !== village.ownerAccountId) {
        await tell(client, world, village.ownerAccountId, {
          kind: 'caravan_delivered',
          tier: 'digest',
          title: `A caravan from ${sender.name} reached ${village.name}`,
          body: `It brought ${total(caravan.cargo) - total(received.leftover)} resources.`,
        }, event.dueAt);
      }
    }
    await markReturning(client, caravan.id, carriedBack);
    await planAmbushes(client, data, world, { ...caravan, status: 'returning', carriedBack }, 'back', event.dueAt);
    const payload: CaravanPayload = { caravanId: caravan.id };
    await scheduleEvent(client, world.id, caravan.returnsAt, 'caravan_return', payload);
    await notifyWorld(client, { worldId: world.id, type: 'caravans' });
  },

  // Home again. What doesn't fit in a full storehouse is lost.
  async caravan_return({ client, world }, event) {
    const caravan = await loadCaravan(client, caravanPayload.parse(event.payload).caravanId);
    if (caravan.status !== 'returning') return;
    const village = await loadVillage(client, caravan.villageId);
    const received = receive(village.state.ledger, event.dueAt, caravan.carriedBack ?? emptyResources());
    // Its escort is home too.
    let state = village.state;
    for (const [unit, n] of Object.entries(caravan.escort)) state = returnHome(state, unit, n);
    await saveVillageState(client, village.id, { ...state, ledger: received.ledger });
    await markCaravanDone(client, caravan.id);
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    await notifyWorld(client, { worldId: world.id, type: 'caravans' });
  },

  async vault_upgrade({ client, world }) {
    const vault = await loadVault(client, world.id);
    if (vault.upgradingTo === null) return;
    await saveVault(client, { ...vault, level: vault.upgradingTo, upgradingTo: null, upgradeCompletesAt: null });
    await notifyWorld(client, { worldId: world.id, type: 'caravans' });
  },
};
