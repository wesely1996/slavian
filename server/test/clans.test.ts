import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { againstFront, clanBonuses, hasClan, villageBonuses } from '../src/sim/clans.js';
import { setupFactors } from '../src/sim/field.js';
import { researchMs, trainFactor } from '../src/sim/research.js';
import { completeBuild, newVillage, queueBuild, queueTraining, villageRates, withBonuses } from '../src/sim/village.js';
import { fortCost } from '../src/scheduler/field.js';

const data = loadGameData();
const T0 = new Date('2026-02-01T12:00:00Z');

function rich(clan: string | null, level = 0, building = 'barracks') {
  const fresh = withBonuses(data, newVillage(data, T0, 1), clanBonuses(data, clan), T0, 1);
  let state = {
    ...fresh,
    ledger: { ...fresh.ledger, amounts: { wood: 9e5, stone: 9e5, grain: 9e5, iron: 9e5 }, capacity: { wood: 9e9, stone: 9e9, grain: 9e9, iron: 9e9 } },
  };
  for (let target = 1; target <= level; target++) {
    const { state: queued, queued: item } = queueBuild(data, state, building, state.ledger.settledAt, 1);
    state = completeBuild(data, queued, item.plot, target, item.completesAt, 1);
  }
  return state;
}

describe('clans', () => {
  it('has six clans, each with a story, a weakness and its own unit or building', () => {
    expect(Object.keys(data.clans.clans).sort()).toEqual(['bobr', 'jelen', 'medved', 'rys', 'sokol', 'volk']);
    for (const clan of Object.values(data.clans.clans)) {
      expect(clan.story.length).toBeGreaterThan(20);
      expect(Object.values(clan.effects).some((v) => v < 0) || clan.effects.researchTime! > 0 || clan.effects.fortCost! > 0 || clan.effects['trainTime.settler']! > 0).toBe(true);
    }
  });

  it('adds the clan to its bonuses, marked so its own units can be told apart', () => {
    const bonuses = clanBonuses(data, 'rys');
    expect(bonuses['production.wood']).toBe(0.15);
    expect(hasClan(bonuses, 'rys')).toBe(true);
    expect(hasClan(bonuses, 'sokol')).toBe(false);
    expect(clanBonuses(data, null)).toEqual({});
  });

  it('lets only the clan train its unique unit', () => {
    const sokol = rich('sokol', 2, 'shooting_range');
    expect(() => queueTraining(data, sokol, 'forest_archer', 1, sokol.ledger.settledAt, 1)).toThrow(/Only Rod Rysa can train a Forest Archer/);
    const rys = rich('rys', 2, 'shooting_range');
    expect(queueTraining(data, rys, 'forest_archer', 1, rys.ledger.settledAt, 1).batch.unit).toBe('forest_archer');
  });

  it('lets only the clan build its unique building, which adds its effects per level', () => {
    expect(() => queueBuild(data, rich('rys'), { plot: 'c2', building: 'stone_redoubt' }, T0, 1)).toThrow(/Only Rod Medvěda/);
    let state = rich('medved');
    for (let level = 1; level <= 2; level++) {
      const { state: queued, queued: item } = queueBuild(data, state, { plot: 'c2', building: 'stone_redoubt' }, state.ledger.settledAt, 1);
      state = completeBuild(data, queued, item.plot, level, item.completesAt, 1);
    }
    expect(villageBonuses(data, state).homeDefense).toBeCloseTo(0.1 + 2 * 0.04);
    expect(state.bonuses.homeDefense).toBe(0.1);
  });

  it('feeds the Granary-Temple into grain production', () => {
    let state = rich('jelen');
    const before = villageRates(data, state, 1).grain;
    const { state: queued, queued: item } = queueBuild(data, state, { plot: 'c2', building: 'granary_temple' }, state.ledger.settledAt, 1);
    state = completeBuild(data, queued, item.plot, 1, item.completesAt, 1);
    expect(villageRates(data, state, 1).grain).toBeGreaterThan(before);
  });

  it('applies weaknesses and strengths in their places', () => {
    expect(trainFactor(clanBonuses(data, 'medved'), 'settler')).toBeCloseTo(1.5);
    expect(trainFactor(clanBonuses(data, 'medved'), 'spearman')).toBe(1);
    const tech = Object.keys(data.research.techs)[0]!;
    expect(researchMs(data, tech, 1, clanBonuses(data, 'rys'))).toBe(Math.round(researchMs(data, tech, 1) * 1.2));
    expect(fortCost(data, clanBonuses(data, 'sokol')).stone).toBe(Math.round(data.field.fort.cost.stone * 1.3));
    expect(fortCost(data, {}).stone).toBe(data.field.fort.cost.stone);
    expect(againstFront(clanBonuses(data, 'volk'), 'north')['defense.all']).toBeCloseTo(0.2);
    expect(againstFront(clanBonuses(data, 'volk'), 'south')['defense.all']).toBeUndefined();
    const ambush = { ambush: true, choke: false, fort: false };
    expect(setupFactors(data, ambush, { round: 1, holdersStance: 'balanced', ambushBonus: 0.15 }).holderAttack).toBeCloseTo(1 + data.field.ambush.bonus + 0.15);
  });
});
