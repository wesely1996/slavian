// Raids on the scheduler (data/raids.json): an army sent to raid a front
// marches to the map's edge on its side (army_arrive), then fights one
// stage every stageHours (raid_stage): `depth` field battles, then the
// siege of the front's stronghold. Battles won bring loot (as much as it
// can carry), the North's rare finds, and the front's hatred; a raid beaten,
// or done, comes home with what it carries.
import { villageBonuses } from '../sim/clans.js';
import { z } from 'zod';
import type { GameData, Stance } from '../data/index.js';
import { loadArmy, saveArmy, type Army, type ArmyRaid } from '../db/armies.js';
import { insertBattle, recordRound, type RoundLog } from '../db/battles.js';
import { heroWithArmy, loadHero, saveHero } from '../db/heroes.js';
import { generalWithArmy } from '../db/generals.js';
import { notifyWorld } from '../db/notify.js';
import type { DbClient } from '../db/pool.js';
import { addScroll, listScrolls } from '../db/sites.js';
import { loadVillage } from '../db/villages.js';
import { addEmbers, listMembers, type World } from '../db/worlds.js';
import { RuleError } from '../errors.js';
import { playerStats, total } from '../sim/battle.js';
import { combine, heroBonuses } from '../sim/heroes.js';
import { generalBonuses } from '../sim/generals.js';
import { hex } from '../sim/hex.js';
import type { Front } from '../sim/mapgen.js';
import { carryHome, northFinds, raidBattle, raidCapacity, raidEdge, raidLoot, raidStage, type RaidFind } from '../sim/raids.js';
import { emptyResources } from '../sim/resources.js';
import { createRng } from '../sim/rng.js';
import { combatants, withIntel } from '../sim/scouting.js';
import { armyLosses, dispatchArmy, sendHome, terrainOf } from './armies.js';
import { scheduleEvent, type HandlerRegistry } from './events.js';
import { generalAfterBattle } from './generals.js';
import { heroAfterBattle } from './heroes.js';
import { tell } from './notices.js';
import { refreshBonuses } from './research.js';
import { angerHorde } from './waves.js';

const MS_PER_HOUR = 3_600_000;

export const raidStagePayload = z.object({ armyId: z.number().int(), stage: z.number().int().positive() });
export type RaidStagePayload = z.infer<typeof raidStagePayload>;

export interface RaidOrder {
  homeVillageId: number;
  front: Front;
  depth: number;
  units: Record<string, number>;
  withHero?: boolean | undefined;
  generalId?: number | undefined;
  stance?: Stance | undefined;
  at: Date;
}

function stageMs(data: GameData, worldSpeed: number): number {
  return (data.raids.stageHours * MS_PER_HOUR) / worldSpeed;
}

// Sends an army from a village to raid a front's lands.
export async function startRaid(client: DbClient, data: GameData, world: World, input: RaidOrder): Promise<Army> {
  if (!world.activeFronts.includes(input.front)) throw new RuleError('No enemy comes from that side in this world');
  if (!Number.isInteger(input.depth) || input.depth < 1 || input.depth > data.raids.maxDepth) throw new RuleError(`A raid goes 1 to ${data.raids.maxDepth} fields deep`);
  if (world.radius === null) throw new RuleError('This world has no map yet');
  const home = await loadVillage(client, input.homeVillageId);
  const edge = raidEdge(data, await terrainOf(client, world.id), world.radius, input.front, hex(home.q, home.r));
  if (!edge) throw new RuleError('There is no way out to that side of the map');
  const army = await dispatchArmy(client, data, world, {
    homeVillageId: home.id,
    targetVillageId: null,
    targetHex: edge,
    units: input.units,
    orders: 'raid',
    withHero: input.withHero,
    generalId: input.generalId,
    stance: input.stance,
    at: input.at,
  });
  const raid: ArmyRaid = { front: input.front, depth: input.depth, stage: 0, battles: [], finds: [] };
  const raiding: Army = { ...army, raid, loot: emptyResources() };
  await saveArmy(client, raiding);
  return raiding;
}

// At the map's edge: it stands there (beyond it, in the enemy's lands) and
// the first battle comes one stage later.
export async function reachEdge(client: DbClient, data: GameData, world: World, army: Army, at: Date): Promise<void> {
  if (!army.raid) {
    await sendHome(client, world, army, at, data);
    return;
  }
  await saveArmy(client, { ...army, status: 'stationed' });
  const payload: RaidStagePayload = { armyId: army.id, stage: army.raid.stage + 1 };
  await scheduleEvent(client, world.id, new Date(at.getTime() + stageMs(data, world.speed)), 'raid_stage', payload);
}

// Waves so far (the newest wave's index, + 1): the enemy grows with them.
async function wavesSoFar(client: DbClient, worldId: number, at: Date): Promise<number> {
  const { rows } = await client.query<{ n: number | null }>(
    'SELECT MAX(index) AS n FROM waves WHERE world_id = $1 AND band_of IS NULL AND spawn_at <= $2',
    [worldId, at],
  );
  return rows[0]?.n === null || rows[0]?.n === undefined ? 0 : Number(rows[0].n) + 1;
}

// A North find made concrete, seeded by the raid: gear the hero lacks, a
// scroll the group lacks (else nothing), or an Ember.
function pickFind(data: GameData, find: RaidFind, owned: Set<string>, found: Set<string>, seed: number): { kind: 'gear'; item: string } | { kind: 'scroll'; scroll: string } | { kind: 'ember' } | null {
  const rng = createRng(seed >>> 0);
  if (find.type === 'ember') return { kind: 'ember' };
  if (find.type === 'gear') {
    const items = Object.keys(data.heroes.items).filter((i) => !owned.has(i)).sort();
    return items.length ? { kind: 'gear', item: items[Math.floor(rng() * items.length)]! } : null;
  }
  const scrolls = Object.keys(data.lore.scrolls).filter((s) => !found.has(s)).sort();
  return scrolls.length ? { kind: 'scroll', scroll: scrolls[Math.floor(rng() * scrolls.length)]! } : null;
}

// The next horde of a front hates the more for a raid.
async function angerFront(client: DbClient, data: GameData, world: World, front: Front, amount: number, at: Date): Promise<void> {
  if (amount <= 0) return;
  const { rows } = await client.query<{ id: number }>(
    `SELECT id FROM waves WHERE world_id = $1 AND front = $2 AND status = 'scheduled' AND band_of IS NULL ORDER BY spawn_at, id LIMIT 1`,
    [world.id, front],
  );
  if (rows[0]) await angerHorde(client, data, world, rows[0].id, amount, at);
}

export const raidHandlers: HandlerRegistry = {
  async raid_stage({ client, data, world }, event) {
    const payload = raidStagePayload.parse(event.payload);
    const army = await loadArmy(client, payload.armyId).catch(() => null);
    if (!army || army.status !== 'stationed' || army.orders !== 'raid' || !army.raid || army.raid.stage + 1 !== payload.stage) return;
    const at = event.dueAt;
    const raid = army.raid;
    const front = raid.front;
    const stage = raidStage(data, {
      front,
      depth: raid.depth,
      stage: payload.stage,
      waves: await wavesSoFar(client, world.id, at),
      seed: world.seed,
      id: army.id,
      players: (await listMembers(client, world.id)).length,
    });
    const home = await loadVillage(client, army.homeVillageId);
    const hero = await heroWithArmy(client, army.id);
    const general = await generalWithArmy(client, army.id);
    // The home village's buildings count (a Ranch's riders).
    const owned = villageBonuses(data, home.state);
    const heroic = hero ? combine(owned, heroBonuses(data, hero)) : owned;
    const bonuses = general ? combine(heroic, generalBonuses(data, general)) : heroic;
    const fighters = combatants(data, army.units);
    const result = raidBattle(data, {
      army: fighters,
      armyStats: withIntel(data, army.units, playerStats(data, bonuses, false)),
      armyStance: army.stance,
      stage,
      front,
      seed: world.seed,
      id: army.id * 8 + payload.stage,
    });
    // Reports keep the enemy as the attacker, like every other battle.
    const battle = await insertBattle(client, {
      worldId: world.id,
      waveId: null,
      villageId: null,
      q: army.targetQ,
      r: army.targetR,
      setup: { raid: { front, name: stage.name, stronghold: stage.stronghold, stage: payload.stage } },
      attackerStance: stage.stronghold ? data.raids.stronghold.stance : data.raids.fieldStance,
      attackerInitial: stage.enemy,
      defenderInitial: army.units,
      startedAt: at,
    });
    const kills = total(stage.enemy) - total(result.enemyNow);
    const lost: Record<string, number> = {};
    for (const [unit, n] of Object.entries(fighters)) if (n - (result.armyNow[unit] ?? 0) > 0) lost[unit] = n - (result.armyNow[unit] ?? 0);
    let after = await armyLosses(client, data, world, army, lost, at);
    const carried = after.loot ?? emptyResources();
    const loot = result.won ? carryHome(carried, raidLoot(data, front, kills, stage.stronghold), raidCapacity(data, after.units)) : carried;
    for (const [i, round] of result.rounds.entries()) {
      const log: RoundLog = {
        round: round.round,
        at: at.toISOString(),
        attackerLosses: round.defenderLosses,
        defenderLosses: round.attackerLosses,
        attackerLeft: round.defenderLeft,
        defenderLeft: round.attackerLeft,
      };
      const last = i === result.rounds.length - 1;
      await recordRound(client, battle.id, log, last ? { status: result.won ? 'cleared' : 'repelled', at, loot: result.won ? loot : null } : null);
    }
    if (hero) {
      await heroAfterBattle(client, data, world, result.won ? hero : { ...hero, villageId: army.homeVillageId, armyId: null }, { kills, won: result.won, battleId: battle.id, at });
    }
    if (general) await generalAfterBattle(client, data, world, general, { kills, won: result.won, at });
    const finds: string[] = [];
    if (result.won) {
      await angerFront(client, data, world, front, data.raids.hatred.perBattle + (stage.stronghold ? data.raids.hatred.stronghold : 0), at);
      // The North: rare finds besides.
      if (front === 'north') {
        const ownerHero = hero ?? (army.ownerAccountId !== null ? await loadHero(client, world.id, army.ownerAccountId).catch(() => null) : null);
        for (const [i, find] of northFinds(data, { stronghold: stage.stronghold, seed: world.seed, id: army.id, stage: payload.stage }).entries()) {
          const current = ownerHero ? await loadHero(client, world.id, ownerHero.accountId) : null;
          const owned = new Set(current ? [...current.inventory, ...Object.values(current.gear)] : []);
          const found = new Set((await listScrolls(client, world.id)).map((s) => s.scroll));
          const picked = pickFind(data, find, owned, found, world.seed ^ Math.imul(army.id + 1, 0x9e3779b1) ^ (payload.stage * 16 + i));
          if (!picked) continue;
          if (picked.kind === 'ember') {
            await addEmbers(client, world.id, 1);
            finds.push("a Svarog's Ember");
          } else if (picked.kind === 'gear' && current) {
            await saveHero(client, { ...current, inventory: [...current.inventory, picked.item] });
            await notifyWorld(client, { worldId: world.id, type: 'heroes' });
            finds.push(data.heroes.items[picked.item]?.name ?? picked.item);
          } else if (picked.kind === 'scroll') {
            await addScroll(client, world.id, { scroll: picked.scroll, accountId: army.ownerAccountId, siteId: null, foundAt: at });
            await refreshBonuses(client, data, world, (await listMembers(client, world.id)).map((m) => m.accountId), at);
            await notifyWorld(client, { worldId: world.id, type: 'research' });
            finds.push(`the scroll "${data.lore.scrolls[picked.scroll]?.name ?? picked.scroll}"`);
          }
        }
      }
    }
    const entry = { stage: payload.stage, name: stage.name, stronghold: stage.stronghold, won: result.won, battleId: battle.id, kills, lost: total(lost) };
    const nextRaid: ArmyRaid = { ...raid, stage: payload.stage, battles: [...raid.battles, entry], finds: [...raid.finds, ...finds] };
    after = { ...after, raid: nextRaid, loot };
    const done = !result.won || stage.stronghold || total(combatants(data, after.units)) === 0;
    if (done) {
      await sendHome(client, world, after, at, data);
    } else {
      await saveArmy(client, after);
      const next: RaidStagePayload = { armyId: army.id, stage: payload.stage + 1 };
      await scheduleEvent(client, world.id, new Date(at.getTime() + stageMs(data, world.speed)), 'raid_stage', next);
    }
    const found = finds.length ? ` and ${finds.join(', ')}` : '';
    await tell(client, world, army.ownerAccountId, {
      kind: 'battle_result',
      tier: done ? 'push' : 'digest',
      title: result.won
        ? stage.stronghold
          ? 'Your raid sacked the {name}'
          : 'Your raid won the battle of the {name}'
        : 'Your raid was beaten at the {name}',
      body: result.won
        ? stage.stronghold
          ? 'It comes home with {loot} resources{found}.'
          : '{kills} of the enemy fell; it carries {loot} resources{found} and marches on.'
        : 'It turns for home with {loot} resources; {lost} of its men fell.',
      vars: { name: stage.name, kills, loot: total(loot), found, lost: total(lost) },
    }, at);
    await notifyWorld(client, { worldId: world.id, type: 'battles' });
    await notifyWorld(client, { worldId: world.id, type: 'armies' });
  },
};
