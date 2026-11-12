// Heroes and generals in battle (sim/battle.ts Champion): they lead their
// troops and fight in the ranks. One commands: the hero if there is one,
// else the general, who takes the hero's place when the hero falls. A
// champion struck down falls: a hero is carried home wounded, a general dies.
import { achieve } from './achievements.js';
import type { GameData } from '../data/index.js';
import type { General } from '../db/generals.js';
import type { Hero } from '../db/heroes.js';
import type { DbClient } from '../db/pool.js';
import type { World } from '../db/worlds.js';
import { championOf, type Champion } from '../sim/battle.js';
import { generalBonuses } from '../sim/generals.js';
import { combine, heroBonuses } from '../sim/heroes.js';
import { bonus, type Bonuses } from '../sim/research.js';
import { generalAfterBattle } from './generals.js';
import { heroAfterBattle } from './heroes.js';

// `base` with the commander's bonuses: the hero's, else the general's.
export function commandBonuses(data: GameData, base: Bonuses, hero: Hero | null, general: General | null): Record<string, number> {
  if (hero) return combine(base, heroBonuses(data, hero));
  if (general) return combine(base, generalBonuses(data, general));
  return { ...base };
}

// The champions fighting with a force: its hero, its general, the stronger
// for the owner's `champion` and `generalChampion` bonuses (a hero's own).
export function championsOf(data: GameData, hero: Hero | null, general: General | null, owned: Bonuses = {}): Champion[] {
  const stronger = (c: Champion, key: string): Champion => {
    const f = 1 + bonus(owned, key);
    return f === 1 ? c : { ...c, attack: c.attack * f, defense: c.defense * f, health: c.health * f };
  };
  return [
    ...(hero ? [stronger(championOf(data, 'hero', hero.level), 'champion')] : []),
    ...(general ? [stronger(championOf(data, 'general', general.level), 'generalChampion')] : []),
  ];
}

// Champions struck down in a round: a hero is wounded (with an army, carried
// home to `homeVillageId`), a general dies.
export async function championsFall(
  client: DbClient,
  data: GameData,
  world: World,
  fallen: readonly string[],
  force: { hero: Hero | null; general: General | null; homeVillageId: number | null },
  input: { kills: number; battleId: number; at: Date },
): Promise<void> {
  if (fallen.includes('hero') && force.hero) {
    const hero = force.homeVillageId === null ? force.hero : { ...force.hero, villageId: force.homeVillageId, armyId: null };
    await heroAfterBattle(client, data, world, hero, { kills: input.kills, won: false, battleId: input.battleId, at: input.at });
    await achieve(client, data, world, hero.accountId, 'hero_fallen', input.at);
  }
  if (fallen.includes('general') && force.general) {
    await generalAfterBattle(client, data, world, force.general, { kills: input.kills, won: false, at: input.at });
  }
}
