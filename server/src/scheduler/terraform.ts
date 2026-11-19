// Terraforming (field.json terraform): a village reshapes the land near it.
// A forest cleared (its timber brought home), trees planted, a swamp
// drained: paid at once, the hex's terrain changes when the work is done.
import { z } from 'zod';
import type { GameData, TerrainId } from '../data/index.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { deleteTerraform, insertTerraform, terraformAt, type Terraform } from '../db/terraforms.js';
import { listVillages, loadVillage, saveVillageState } from '../db/villages.js';
import { loadHexes, setHexTerrain, type World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { hex, hexDistance, hexKey, neighbors, type Hex } from '../sim/hex.js';
import { createRng } from '../sim/rng.js';
import { outpostHex, outpostPlots, raidOutpost } from '../sim/village.js';
import { deleteCamp, listCamps } from '../db/camps.js';
import { deleteFort, listForts } from '../db/forts.js';
import { receive } from '../sim/logistics.js';
import { spend } from '../sim/resources.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { takenHexes } from './horde.js';
import { tell, tellOwner } from './notices.js';
import { avoidFire } from './detours.js';
import { armiesHolding } from '../db/armies.js';
import { insertWave, lastWave } from '../db/waves.js';
import { listMembers } from '../db/worlds.js';
import { fleeing } from '../sim/camps.js';
import type { Front } from '../sim/mapgen.js';
import { threatOf } from '../sim/waves.js';
import { angerFront, setOutNow } from './waves.js';

const workPayload = z.object({ q: z.number().int(), r: z.number().int() });
const firePayload = z.object({ q: z.number().int(), r: z.number().int(), action: z.string(), generation: z.number().int(), villageId: z.number().int().nullable() });

// Whether a fire set at `from` at `at` catches on `to` (spreadChance): one
// roll for each neighbouring hex, from the world's seed.
export function fireCatches(seed: number, to: Hex, at: Date, chance: number): boolean {
  const rng = createRng((seed ^ Math.imul(to.q + 1000, 0x632be5ab) ^ Math.imul(to.r + 1000, 0x5bd1e995) ^ (Math.floor(at.getTime() / 60_000) & 0xfffff)) >>> 0);
  return rng() < chance;
}

// A fire has just caught at `work`'s hex: it may spread to each
// neighbouring hex it could burn (never a settlement), spreadHours later.
async function spreadFire(client: DbClient, data: GameData, world: World, work: Terraform, at: Date): Promise<void> {
  const def = data.field.terraform.actions[work.action]!;
  const fire = def.fire!;
  if (work.generation >= fire.generations) return;
  const terrain = new Map<string, TerrainId>((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t]));
  const settled = new Set((await listVillages(client, world.id)).map((v) => hexKey(hex(v.q, v.r))));
  for (const next of neighbors(work.cell)) {
    const type = terrain.get(hexKey(next));
    if (!type || !def.from[type] || settled.has(hexKey(next))) continue;
    // An army standing there keeps the fire off.
    if ((await armiesHolding(client, world.id, next.q, next.r, ['stationed', 'engaged'])).length) continue;
    if ((await terraformAt(client, world.id, next))?.action === work.action) continue;
    if (!fireCatches(world.seed, next, at, fire.spreadChance)) continue;
    await scheduleEvent(client, world.id, new Date(at.getTime() + (fire.spreadHours * 3_600_000) / world.speed), 'fire_spread', {
      q: next.q,
      r: next.r,
      action: work.action,
      generation: work.generation + 1,
      villageId: work.villageId,
    });
  }
}

// The fire reaches a hex: whatever stands there burns (outposts to ruins,
// forts, supply points and camps gone), and it burns for its hours.
async function catchFire(client: DbClient, data: GameData, world: World, cell: Hex, action: string, generation: number, villageId: number | null, at: Date): Promise<void> {
  const def = data.field.terraform.actions[action];
  if (!def?.fire) return;
  const type = new Map<string, TerrainId>((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t])).get(hexKey(cell));
  const villages = await listVillages(client, world.id);
  if (!type || !def.from[type] || villages.some((v) => v.q === cell.q && v.r === cell.r)) return;
  if ((await armiesHolding(client, world.id, cell.q, cell.r, ['stationed', 'engaged'])).length) return;
  const there = await terraformAt(client, world.id, cell);
  if (there?.action === action) return;
  if (there) await deleteTerraform(client, world.id, cell);
  for (const village of villages) {
    const plot = outpostPlots(village.state.plots).find((p) => hexKey(outpostHex(p)!) === hexKey(cell));
    if (!plot || village.state.plots[plot]!.level <= 0) continue;
    let state = village.state;
    while (state.plots[plot]!.level > 0) state = raidOutpost(data, state, plot, at, world.speed);
    await saveVillageState(client, village.id, state);
    await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
    await tell(client, world, village.ownerAccountId, {
      kind: 'outpost_raided',
      tier: 'push',
      title: 'Fire burned an outpost of {village}',
      body: 'The outpost at ({q}, {r}) lies in ruins.',
      vars: { village: village.name, q: cell.q, r: cell.r },
    }, at);
  }
  for (const fort of await listForts(client, world.id)) {
    if (fort.q !== cell.q || fort.r !== cell.r) continue;
    await deleteFort(client, fort.id);
    await tell(client, world, fort.ownerAccountId, {
      kind: 'outpost_raided',
      tier: 'push',
      title: 'Fire burned your stronghold at ({q}, {r})',
      body: 'Nothing is left of it, nor of its grain.',
      vars: { q: cell.q, r: cell.r },
    }, at);
  }
  await burnCamps(client, data, world, cell, at);
  const work: Terraform = { cell, action, villageId, completesAt: new Date(at.getTime() + (def.hours * 3_600_000) / world.speed), generation };
  await insertTerraform(client, world.id, work);
  await scheduleEvent(client, world.id, work.completesAt, 'terraform_done', { q: cell.q, r: cell.r });
  await avoidFire(client, data, world, cell, work.completesAt, at);
  await spreadFire(client, data, world, work, at);
  await notifyWorld(client, { worldId: world.id, type: 'armies' });
  await notifyWorld(client, { worldId: world.id, type: 'world' });
}

// A camp on a burning hex is gone. A bandit camp's or a lair's survivors
// (camps.json burnt) flee at once as a small horde of its front from where
// it stood, on the nearest player village, and the front hates the more.
async function burnCamps(client: DbClient, data: GameData, world: World, cell: Hex, at: Date): Promise<void> {
  for (const camp of await listCamps(client, world.id)) {
    if (camp.q !== cell.q || camp.r !== cell.r) continue;
    await deleteCamp(client, camp.id);
    if (camp.kind !== 'bandit' && camp.kind !== 'lair') continue;
    const fled = fleeing(data, camp.units, world.seed, camp.id);
    const count = Object.values(fled).reduce((sum, n) => sum + n, 0);
    if (count > 0) {
      const last = await lastWave(client, world.id);
      const wave = await insertWave(
        client,
        world.id,
        { index: last?.index ?? 0, front: camp.front as Front, spawnAt: at, composition: fled, threat: threatOf(data, fled), stance: 'offensive' },
        false,
        last?.id ?? null,
        { kind: 'fled', target: null, from: { q: camp.q, r: camp.r } },
      );
      // They flee at once, not at the scheduler's next pass.
      await setOutNow(client, data, world, wave.id, at);
      for (const member of await listMembers(client, world.id)) {
        await tell(client, world, member.accountId, {
          kind: 'camp',
          tier: 'push',
          title: 'The camp at ({q}, {r}) burns',
          body: '{count} of them flee the flames and march on the villages.',
          vars: { q: camp.q, r: camp.r, count },
        }, at);
      }
    }
    await angerFront(client, data, world, camp.front as Front, data.camps.burnt.hatred, at);
    await notifyWorld(client, { worldId: world.id, type: 'waves' });
  }
}

// Why `action` can't be done on a hex of `terrain` `distance` from the
// village ('' when it can): the rules that need no database.
export function terraformProblem(data: GameData, action: string, terrain: TerrainId | undefined, distance: number, taken: boolean, busy: boolean, held = false): string {
  const rules = data.field.terraform;
  const def = rules.actions[action];
  if (!def) return 'No such work';
  if (taken) return 'Something stands there';
  if (def.fire && held) return 'An army stands there';
  if (distance < 1 || distance > rules.range) return `Land is reshaped within ${rules.range} hexes of the village`;
  if (busy) return 'Work is already under way there';
  if (!terrain || !def.from[terrain]) return 'That work cannot be done on this land';
  return '';
}

// Whether a bandit camp or a lair stands on `cell` (and nothing else there).
async function burnableCampAt(client: DbClient, worldId: number, cell: Hex): Promise<boolean> {
  return (await listCamps(client, worldId)).some((c) => c.q === cell.q && c.r === cell.r && (c.kind === 'bandit' || c.kind === 'lair'));
}

export async function startTerraform(client: DbClient, data: GameData, world: World, villageId: number, cell: Hex, action: string, at: Date): Promise<Terraform> {
  const village = await loadVillage(client, villageId);
  const terrain = new Map<string, TerrainId>((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t])).get(hexKey(cell));
  const problem = terraformProblem(
    data,
    action,
    terrain,
    hexDistance(cell, hex(village.q, village.r)),
    // A fire may be set on a bandit camp or a lair, to burn it out.
    (await takenHexes(client, world.id)).has(hexKey(cell)) && !(data.field.terraform.actions[action]?.fire && (await burnableCampAt(client, world.id, cell))),
    (await terraformAt(client, world.id, cell)) !== null,
    (await armiesHolding(client, world.id, cell.q, cell.r, ['stationed', 'engaged'])).length > 0,
  );
  if (problem) throw new RuleError(problem);
  const def = data.field.terraform.actions[action]!;
  await saveVillageState(client, village.id, { ...village.state, ledger: spend(village.state.ledger, at, def.cost) });
  const work: Terraform = { cell, action, villageId: village.id, completesAt: new Date(at.getTime() + (def.hours * 3_600_000) / world.speed), generation: 0 };
  await insertTerraform(client, world.id, work);
  await scheduleEvent(client, world.id, work.completesAt, 'terraform_done', { q: cell.q, r: cell.r });
  if (def.fire) {
    await burnCamps(client, data, world, cell, at);
    await avoidFire(client, data, world, cell, work.completesAt, at);
    await spreadFire(client, data, world, work, at);
  }
  await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
  await notifyWorld(client, { worldId: world.id, type: 'world' });
  return work;
}

export const terraformHandlers: HandlerRegistry = {
  async fire_spread({ client, data, world }, event) {
    const p = firePayload.parse(event.payload);
    await catchFire(client, data, world, hex(p.q, p.r), p.action, p.generation, p.villageId, event.dueAt);
  },

  async terraform_done({ client, data, world }, event) {
    const cell = hex(workPayload.parse(event.payload).q, workPayload.parse(event.payload).r);
    const work = await terraformAt(client, world.id, cell);
    if (!work || work.completesAt.getTime() !== event.dueAt.getTime()) return;
    await deleteTerraform(client, world.id, cell);
    const def = data.field.terraform.actions[work.action];
    const terrain = new Map<string, TerrainId>((await loadHexes(client, world.id)).map(([q, r, t]) => [`${q},${r}`, t])).get(hexKey(cell));
    const into = def && terrain ? def.from[terrain] : undefined;
    if (into) await setHexTerrain(client, world.id, cell.q, cell.r, into);
    if (work.villageId !== null) {
      const village = await loadVillage(client, work.villageId).catch(() => null);
      // A fire tells only the one who set it, where they set it.
      if (village && village.ownerAccountId !== null && work.generation === 0) {
        if (def?.gain) await saveVillageState(client, village.id, { ...village.state, ledger: receive(village.state.ledger, event.dueAt, def.gain).ledger });
        await tellOwner(
          client,
          world,
          village.id,
          (name) => ({ kind: 'build_done', tier: 'digest', title: 'The land near {village} is reshaped', body: 'The work at ({q}, {r}) is done.', vars: { village: name, q: cell.q, r: cell.r } }),
          event.dueAt,
        );
        await notifyWorld(client, { worldId: world.id, type: 'village', villageId: village.id });
      }
    }
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },
};
