import { describe, expect, it } from 'vitest';
import { loadGameData, RESEARCH_BRANCHES } from '../src/data/index.js';
import { playerStats, raidLoot } from '../src/sim/battle.js';
import { caravansFor } from '../src/sim/logistics.js';
import { bonusesOf, researchProblem, timeFactor } from '../src/sim/research.js';
import { scoutTravelMs, survivorsOf } from '../src/sim/scouting.js';
import { hex } from '../src/sim/hex.js';
import { capacity, newVillage, productionPerHour, queueBuild, queueTraining, villageRates } from '../src/sim/village.js';

const data = loadGameData();
const T0 = new Date('2026-05-01T00:00:00Z');

describe('the tech tree', () => {
  it('has about thirty techs across five branches, each reachable', () => {
    const techs = Object.entries(data.research.techs);
    expect(techs.length).toBeGreaterThanOrEqual(24);
    expect(new Set(techs.map(([, t]) => t.branch))).toEqual(new Set(RESEARCH_BRANCHES));
    for (const [id, tech] of techs) {
      for (const required of tech.requires) {
        expect(data.research.techs[required]!.academyLevel, `${id} needs ${required}`).toBeLessThanOrEqual(tech.academyLevel);
      }
    }
  });

  it('checks the Academy, prerequisites and one tech at a time', () => {
    const ok = { academyLevel: 5, done: new Set<string>(), researching: false };
    expect(researchProblem(data, 'felling_axes', ok)).toBeNull();
    expect(researchProblem(data, 'nope', ok)).toMatch(/Unknown tech/);
    expect(researchProblem(data, 'felling_axes', { ...ok, done: new Set(['felling_axes']) })).toMatch(/already known/);
    expect(researchProblem(data, 'felling_axes', { ...ok, researching: true })).toMatch(/one tech at a time/);
    expect(researchProblem(data, 'shield_wall', { ...ok, academyLevel: 1 })).toMatch(/Academy of level 2/);
    expect(researchProblem(data, 'shield_wall', ok)).toMatch(/needs Spear Drill first/);
    expect(researchProblem(data, 'svarog_forge', ok)).toMatch(/needs Drill Yards and Rite of Perun first/);
  });

  it('adds up effects', () => {
    expect(bonusesOf(data, ['field_kitchens', 'veles_ward', 'felling_axes'])).toEqual({ upkeep: -0.2, 'production.wood': 0.1 });
    expect(timeFactor({ buildTime: -5 }, 'buildTime')).toBe(0.1);
  });
});

describe('research effects', () => {
  const v = newVillage(data, T0, 1);

  it('raise production, outposts and storage, and cut upkeep', () => {
    const plain = productionPerHour(data, v.plots, 1);
    const boosted = productionPerHour(data, v.plots, 1, false, { 'production.wood': 0.1, 'production.all': 0.05 });
    expect(boosted.wood).toBeCloseTo(plain.wood * 1.15);
    expect(boosted.iron).toBeCloseTo(plain.iron * 1.05);
    expect(capacity(data, v.plots, { storage: 0.25 }).wood).toBeCloseTo(capacity(data, v.plots).wood * 1.25);
    const fed = { ...v, garrison: { spearman: 10 } };
    const lean = { ...fed, bonuses: { upkeep: -0.5 } };
    // Ten spearmen at home eat 5 grain an hour on garrison rations; half of that is saved.
    expect(villageRates(data, lean, 1).grain - villageRates(data, fed, 1).grain).toBeCloseTo(2.5);
  });

  it('speed up building and training', () => {
    const rich = { ...v, ledger: { ...v.ledger, amounts: { wood: 9e6, stone: 9e6, grain: 9e6, iron: 9e6 } } };
    const plain = queueBuild(data, rich, { plot: 'f0' }, T0, 1).queued;
    const fast = queueBuild(data, { ...rich, bonuses: { buildTime: -0.1 } }, { plot: 'f0' }, T0, 1).queued;
    expect(fast.completesAt.getTime() - T0.getTime()).toBeCloseTo((plain.completesAt.getTime() - T0.getTime()) * 0.9, -2);
    const barracks = { ...rich, levels: { ...rich.levels, barracks: 1 } };
    const slow = queueTraining(data, barracks, 'spearman', 1, T0, 1).batch;
    const quick = queueTraining(data, { ...barracks, bonuses: { trainTime: -0.2 } }, 'spearman', 1, T0, 1).batch;
    expect(quick.perUnitMs).toBe(Math.round(slow.perUnitMs * 0.8));
  });

  it('make troops fight better, at home most of all', () => {
    const bonuses = { 'attack.infantry': 0.1, 'attack.all': 0.05, 'defense.all': 0.05, homeDefense: 0.1 };
    const spear = data.units.units.spearman!;
    expect(playerStats(data, bonuses)('spearman').attack).toBeCloseTo(spear.attack * 1.15);
    expect(playerStats(data, bonuses)('spearman').defense).toBeCloseTo(spear.defense * 1.05);
    expect(playerStats(data, bonuses, true)('spearman').defense).toBeCloseTo(spear.defense * 1.15);
    expect(playerStats(data)('spearman')).toEqual({ family: 'infantry', attack: spear.attack, defense: spear.defense });
  });

  it('hide loot, load caravans fuller and keep scouts alive', () => {
    const stores = { wood: 1000, stone: 1000, grain: 1000, iron: 1000 };
    const horde = { grey_wolf: 10 };
    const hidden = raidLoot(data, stores, horde, horde, { lootTaken: -0.25 }).wood;
    expect(Math.abs(hidden - raidLoot(data, stores, horde, horde).wood * 0.75)).toBeLessThanOrEqual(1);
    expect(caravansFor(data, { wood: 600, stone: 0, grain: 0, iron: 0 })).toBe(2);
    expect(caravansFor(data, { wood: 600, stone: 0, grain: 0, iron: 0 }, { caravanCapacity: 0.25 })).toBe(1);
    const brave = survivorsOf(data, 'north', 200, 7, 1, { scoutSurvival: 0.3 });
    expect(brave).toBeGreaterThan(survivorsOf(data, 'north', 200, 7, 1));
    const terrain = new Map([['0,0', 'plains' as const], ['1,0', 'plains' as const]]);
    expect(scoutTravelMs(data, terrain, hex(0, 0), hex(1, 0), 1, { scoutSpeed: 1 })).toBe(Math.round(scoutTravelMs(data, terrain, hex(0, 0), hex(1, 0), 1) / 2));
  });
});
