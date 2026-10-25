import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { RuleError } from '../src/errors.js';
import { hex } from '../src/sim/hex.js';
import { amountsAt, mapResources } from '../src/sim/resources.js';
import {
  abandonOutpost,
  claimOutpost,
  outpostHex,
  outpostLimit,
  outpostPlots,
  outpostYield,
  raidOutpost,
  setBesieged,
  buildQueueLimit,
  buildSeconds,
  capacity,
  completeBuild,
  demolish,
  fieldsFromLand,
  HALL_PLOT,
  hospitalHealed,
  levelCost,
  newVillage,
  plotsFromLegacyLevels,
  productionPerHour,
  queueBuild,
  trade,
  unlockedSlots,
  type VillageState,
} from '../src/sim/village.js';

const data = loadGameData();
const T0 = new Date('2026-01-01T00:00:00Z');
const woodcutter = data.buildings.buildings.woodcutter!;
const { village } = data.buildings;

function rich(state: VillageState): VillageState {
  return {
    ...state,
    ledger: { ...state.ledger, amounts: { wood: 9e6, stone: 9e6, grain: 9e6, iron: 9e6 }, capacity: { wood: 9e9, stone: 9e9, grain: 9e9, iron: 9e9 } },
  };
}

// Queues and immediately completes one build order.
function build(state: VillageState, order: Parameters<typeof queueBuild>[2]): VillageState {
  const { state: queued, queued: item } = queueBuild(data, state, order, state.ledger.settledAt, 1);
  return completeBuild(data, queued, item.plot, item.targetLevel, item.completesAt, 1);
}

describe('game data', () => {
  it('loads and validates', () => {
    expect(Object.keys(data.buildings.buildings)).toContain('elder_hall');
    expect(village.fields.length).toBeGreaterThan(0);
  });
});

describe('village layout', () => {
  it('starts with fields at level 0 and the Elder\'s Hall in the first slot', () => {
    const v = newVillage(data, T0, 1);
    expect(Object.keys(v.plots).filter((id) => id.startsWith('f'))).toHaveLength(village.fields.length);
    expect(Object.keys(v.plots).filter((id) => id.startsWith('c'))).toHaveLength(village.centerSlots);
    expect(v.plots.f0).toEqual({ building: village.fields[0], level: 0 });
    expect(v.plots[HALL_PLOT]).toEqual({ building: 'elder_hall', level: 1 });
    expect(v.plots.c1).toEqual({ building: null, level: 0 });
    expect(v.levels).toEqual({ elder_hall: 1 });
  });

  it('a founded village takes its fields from the land around it', () => {
    const count = (fields: string[]) => Object.fromEntries([...new Set(fields)].map((f) => [f, fields.filter((x) => x === f).length]));
    const forest = Array<TerrainId>(18).fill('forest');
    expect(count(fieldsFromLand(data, forest))).toEqual({ woodcutter: 9, quarry: 1, farm: 1, iron_mine: 1 });
    // Wood 60, grain 60, stone 36, iron 24: 8 fields shared out, the two left over to the largest remainders.
    const mixed: TerrainId[] = [...Array<TerrainId>(6).fill('forest'), ...Array<TerrainId>(6).fill('plains'), ...Array<TerrainId>(6).fill('hills')];
    const fields = fieldsFromLand(data, mixed);
    expect(fields).toHaveLength(village.fields.length);
    expect(count(fields)).toEqual({ woodcutter: 4, quarry: 2, farm: 4, iron_mine: 2 });
    // Land that yields nothing (or none at all) keeps the balanced layout.
    expect(fieldsFromLand(data, ['ocean', undefined])).toEqual(village.fields);
    const founded = newVillage(data, T0, 1, { startingResources: village.startingResources, adminUpkeep: 0, bonuses: {}, fields: fieldsFromLand(data, forest) });
    expect(founded.plots.f8).toEqual({ building: 'woodcutter', level: 0 });
  });

  it('a bigger Elder\'s Hall unlocks slots and queue places', () => {
    expect(unlockedSlots(data, 1)).toBe(village.slotsUnlockedAtStart);
    expect(unlockedSlots(data, 5)).toBe(village.slotsUnlockedAtStart + 4 * village.slotsPerHallLevel);
    expect(unlockedSlots(data, 99)).toBe(village.centerSlots);
    expect(buildQueueLimit(data, 1)).toBe(village.baseQueueLimit);
    expect(buildQueueLimit(data, 3)).toBe(village.baseQueueLimit + 1);
    expect(buildQueueLimit(data, 9)).toBe(village.baseQueueLimit + 3);
  });
});

describe('building', () => {
  it('upgrades each field on its own; production adds up across fields', () => {
    let v = rich(newVillage(data, T0, 1));
    const base = productionPerHour(data, v.plots, 1).wood;
    v = build(v, { plot: 'f0' });
    v = build(v, { plot: 'f1' });
    v = build(v, { plot: 'f1' });
    expect(v.plots.f0!.level).toBe(1);
    expect(v.plots.f1!.level).toBe(2);
    expect(v.levels.woodcutter).toBe(2);
    const prod = woodcutter.production!;
    expect(productionPerHour(data, v.plots, 1).wood).toBeCloseTo(base + prod.basePerHour + prod.basePerHour * prod.growth);
  });

  it('constructs a building in a free unlocked slot, then upgrades it there', () => {
    let v = rich(newVillage(data, T0, 1));
    v = build(v, { plot: 'c2', building: 'barracks' });
    expect(v.plots.c2).toEqual({ building: 'barracks', level: 1 });
    v = build(v, { plot: 'c2' });
    expect(v.levels.barracks).toBe(2);
  });

  it('refuses locked slots, duplicates, wrong kinds and changing a plot', () => {
    const v = rich(newVillage(data, T0, 1));
    const at = v.ledger.settledAt;
    const locked = `c${village.slotsUnlockedAtStart}`;
    expect(() => queueBuild(data, v, { plot: locked, building: 'barracks' }, at, 1)).toThrow(/locked/);
    expect(() => queueBuild(data, v, { plot: 'c1', building: 'woodcutter' }, at, 1)).toThrow(/fields/);
    expect(() => queueBuild(data, v, { plot: 'c1' }, at, 1)).toThrow(/which building/);
    expect(() => queueBuild(data, v, { plot: 'f0', building: 'farm' }, at, 1)).toThrow(/holds a Woodcutter/);
    expect(() => queueBuild(data, v, { plot: 'x9' }, at, 1)).toThrow(RuleError);
    const withBarracks = queueBuild(data, v, { plot: 'c1', building: 'barracks' }, at, 1).state;
    // Already being built in c1: no second one in c2.
    expect(() => queueBuild(data, withBarracks, { plot: 'c2', building: 'barracks' }, at, 1)).toThrow(/already has/);
  });

  it('unlocks more slots as the hall grows', () => {
    let v = rich(newVillage(data, T0, 1));
    const locked = `c${village.slotsUnlockedAtStart}`;
    v = build(v, { plot: HALL_PLOT });
    expect(() => build(v, { plot: locked, building: 'barracks' })).not.toThrow();
  });

  it('picks a plot for orders that only name a building (older clients)', () => {
    let v = rich(newVillage(data, T0, 1));
    v = build(v, 'woodcutter');
    v = build(v, 'woodcutter');
    // The lowest woodcutter field gets the next upgrade.
    expect([v.plots.f0!.level, v.plots.f1!.level]).toEqual([1, 1]);
    v = build(v, 'storehouse');
    expect(v.plots.c1).toEqual({ building: 'storehouse', level: 1 });
    v = build(v, 'storehouse');
    expect(v.plots.c1!.level).toBe(2);
    expect(capacity(data, v.plots).wood).toBeGreaterThan(village.baseCapacity);
  });

  it('scales cost and time with level, world speed and the hall', () => {
    expect(levelCost(woodcutter, 1)).toEqual(woodcutter.cost);
    expect(levelCost(woodcutter, 2).wood).toBe(Math.round(woodcutter.cost.wood * woodcutter.costGrowth));
    expect(buildSeconds(woodcutter, 1, 10)).toBe(woodcutter.buildSeconds / 10);
    let v = rich(newVillage(data, T0, 1));
    const slow = queueBuild(data, v, { plot: 'f0' }, v.ledger.settledAt, 1).queued;
    v = build(v, { plot: HALL_PLOT });
    const fast = queueBuild(data, v, { plot: 'f0' }, v.ledger.settledAt, 1).queued;
    const span = (q: typeof slow) => q.completesAt.getTime() - q.startsAt.getTime();
    expect(span(fast)).toBeLessThan(span(slow));
  });

  it('queues builds back to back, pays up front and enforces the queue limit', () => {
    const v = newVillage(data, T0, 1);
    const first = queueBuild(data, v, { plot: 'f0' }, T0, 1);
    const second = queueBuild(data, first.state, { plot: 'f6' }, T0, 1);
    expect(second.queued.startsAt).toEqual(first.queued.completesAt);
    expect(second.state.ledger.amounts.wood).toBe(
      village.startingResources.wood - levelCost(woodcutter, 1).wood - data.buildings.buildings.farm!.cost.wood,
    );
    // Fill the queue up to the limit (one build per field); one more is refused.
    let state = second.state;
    const limit = buildQueueLimit(data, 1);
    const fields = ['f1', 'f3', 'f7', 'f10', 'f2', 'f4', 'f8'];
    for (const plot of fields.slice(0, limit - 2)) state = queueBuild(data, state, { plot }, T0, 1).state;
    expect(state.queue).toHaveLength(limit);
    expect(() => queueBuild(data, state, { plot: fields[limit - 2]! }, T0, 1)).toThrow(/queue is full/);
  });

  it('completing raises the plot and production from that moment only', () => {
    const { state, queued } = queueBuild(data, newVillage(data, T0, 1), { plot: 'f0' }, T0, 1);
    const done = completeBuild(data, state, 'f0', 1, queued.completesAt, 1);
    expect(done.ledger.ratesPerHour.wood).toBeGreaterThan(state.ledger.ratesPerHour.wood);
    expect(amountsAt(done.ledger, queued.completesAt)).toEqual(amountsAt(state.ledger, queued.completesAt));
    expect(() => completeBuild(data, state, 'f1', 1, T0, 1)).toThrow(RuleError);
  });
});

describe('legacy villages', () => {
  it('lays out per-building levels on plots', () => {
    const plots = plotsFromLegacyLevels(data, { woodcutter: 3, farm: 1, storehouse: 2, barracks: 1 });
    expect(plots.f0).toEqual({ building: 'woodcutter', level: 3 });
    expect(plots.f6).toEqual({ building: 'farm', level: 1 });
    expect(plots[HALL_PLOT]).toEqual({ building: 'elder_hall', level: 1 });
    expect(plots.c1).toEqual({ building: 'storehouse', level: 2 });
    expect(plots.c2).toEqual({ building: 'barracks', level: 1 });
  });
});

describe('outposts', () => {
  const outpost = data.buildings.buildings.outpost!;
  const home = hex(2, 0);
  const site = (q: number, r: number, terrain: TerrainId = 'forest', taken: string[] = []) => ({
    cell: hex(q, r),
    terrain,
    home,
    taken: new Set(taken),
  });
  const claim = (state: VillageState, s: ReturnType<typeof site>) => claimOutpost(data, state, s, state.ledger.settledAt, 1);
  // Claims and finishes the first level.
  const built = (state: VillageState, s: ReturnType<typeof site>) => {
    const { state: claimed, queued } = claim(state, s);
    return completeBuild(data, claimed, queued.plot, 1, queued.completesAt, 1);
  };

  it('claims a resource hex in range and builds it through the queue', () => {
    const v = rich(newVillage(data, T0, 1));
    const { state, queued } = claim(v, site(3, -2));
    expect(queued).toMatchObject({ plot: 'o3,-2', building: 'outpost', targetLevel: 1 });
    expect(state.plots['o3,-2']).toEqual({ building: 'outpost', level: 0, terrain: 'forest' });
    expect(outpostPlots(state.plots)).toEqual(['o3,-2']);
    expect(outpostHex('o3,-2')).toEqual(hex(3, -2));
    expect(outpostHex('c1')).toBeNull();
    expect(amountsAt(state.ledger, T0).wood).toBe(9e6 - outpost.cost.wood);
  });

  it('refuses hexes out of range, without a yield, taken, or past the limit', () => {
    const v = rich(newVillage(data, T0, 1));
    expect(() => claim(v, site(2, 0))).toThrow(/within 2 hexes/);
    expect(() => claim(v, site(5, 0))).toThrow(/within 2 hexes/);
    expect(() => claim(v, site(3, 0, 'swamp'))).toThrow(/Nothing to gather on Swamp/);
    expect(() => claim(v, site(3, 0, 'forest', ['3,0']))).toThrow(/already taken/);
    const one = claim(v, site(3, 0)).state;
    expect(() => claim(one, site(1, 0))).toThrow(/can hold 1 outpost;/);
    expect(() => queueBuild(data, v, 'outpost', T0, 1)).toThrow(/Pick a hex/);
  });

  it('a bigger Elder\'s Hall allows more outposts', () => {
    expect(outpostLimit(data, 1)).toBe(village.baseOutposts);
    expect(outpostLimit(data, 2)).toBe(village.baseOutposts + 1);
    let v = rich(newVillage(data, T0, 1));
    v = build(v, { plot: HALL_PLOT });
    v = claim(v, site(3, 0)).state;
    expect(claim(v, site(1, 0)).state.plots['o1,0']).toMatchObject({ level: 0 });
  });

  it('gathers by terrain, growing with its level, and stays out of village levels', () => {
    const base = newVillage(data, T0, 1);
    const forest = built(rich(base), site(3, 0, 'forest'));
    const gain = (state: VillageState) => {
      const before = productionPerHour(data, base.plots, 1);
      return mapResources((kind) => Math.round((state.ledger.ratesPerHour[kind] - before[kind]) * 100) / 100);
    };
    expect(gain(forest)).toEqual({ wood: 10, stone: 0, grain: 0, iron: 0 });
    expect(forest.levels).toEqual({ elder_hall: 1 });
    const hills = built(rich(base), site(3, -1, 'hills'));
    expect(gain(hills)).toEqual({ wood: 0, stone: 6, grain: 0, iron: 4 });
    const upgraded = build(hills, { plot: 'o3,-1' });
    expect(upgraded.plots['o3,-1']!.level).toBe(2);
    expect(gain(upgraded).stone).toBeCloseTo(6 * outpost.yieldGrowth!);
    expect(outpostYield(outpost, 'lake', 1, 10).grain).toBe(80);
  });

  it('a raid burns it down a level, to ruins that can be rebuilt', () => {
    let v = build(built(rich(newVillage(data, T0, 1)), site(3, 0)), { plot: 'o3,0' });
    v = raidOutpost(data, v, 'o3,0', v.ledger.settledAt, 1);
    expect(v.plots['o3,0']).toEqual({ building: 'outpost', level: 1, terrain: 'forest', peak: 2 });
    v = raidOutpost(data, v, 'o3,0', v.ledger.settledAt, 1);
    expect(v.plots['o3,0']!.level).toBe(0);
    expect(v.ledger.ratesPerHour.wood).toBeCloseTo(productionPerHour(data, newVillage(data, T0, 1).plots, 1).wood);
    expect(raidOutpost(data, v, 'o3,0', v.ledger.settledAt, 1)).toBe(v);
    expect(build(v, { plot: 'o3,0' }).plots['o3,0']!.level).toBe(1);
  });

  it('can be abandoned, but not while it is being built', () => {
    const v = rich(newVillage(data, T0, 1));
    const { state } = claim(v, site(3, 0));
    expect(() => abandonOutpost(data, state, 'o3,0', state.ledger.settledAt, 1)).toThrow(/being built/);
    const done = built(v, site(3, 0));
    const gone = abandonOutpost(data, done, 'o3,0', done.ledger.settledAt, 1);
    expect(gone.plots['o3,0']).toBeUndefined();
    expect(gone.ledger.ratesPerHour.wood).toBeCloseTo(productionPerHour(data, v.plots, 1).wood);
    expect(() => abandonOutpost(data, v, 'f0', v.ledger.settledAt, 1)).toThrow(/No outpost/);
  });

  it('produces nothing while the village is besieged', () => {
    const v = built(rich(newVillage(data, T0, 1)), site(3, 0));
    const sieged = setBesieged(data, v, true, v.ledger.settledAt, 1);
    expect(sieged.besieged).toBe(true);
    expect(sieged.ledger.ratesPerHour.wood).toBeCloseTo(productionPerHour(data, newVillage(data, T0, 1).plots, 1).wood);
    expect(setBesieged(data, sieged, false, sieged.ledger.settledAt, 1).ledger.ratesPerHour).toEqual(v.ledger.ratesPerHour);
  });
});

describe('more buildings', () => {
  const at = (state: VillageState) => state.ledger.settledAt;

  it('lets storehouses and boosters stand more than once, once their field is high enough', () => {
    let v = rich(newVillage(data, T0, 1));
    v = build(v, { plot: 'c1', building: 'storehouse' });
    v = build(v, { plot: 'c2', building: 'storehouse' });
    // Two storehouses of level 1 hold what each adds above the base.
    expect(capacity(data, v.plots).wood).toBeCloseTo(village.baseCapacity * (1 + 2 * (1.3 - 1)));
    expect(() => build(v, { plot: 'c3', building: 'barracks' })).not.toThrow();
    expect(() => build(build(v, { plot: 'c3', building: 'barracks' }), { building: 'barracks', plot: 'c1' })).toThrow(/holds a Storehouse/);
    expect(() => build(v, { plot: 'c3', building: 'forester' })).toThrow('Forester needs Woodcutter level 5');
    for (let i = 0; i < 5; i++) v = build(v, { plot: 'f0' });
    const forested = build(build(v, { plot: 'c3', building: 'forester' }), { plot: 'c3' });
    expect(forested.ledger.ratesPerHour.wood).toBeCloseTo(productionPerHour(data, forested.plots, 1).wood * 1.1);
  });

  it('tears buildings down for half of what they cost, but not the Hall or fields', () => {
    const v = build(build(rich(newVillage(data, T0, 1)), { plot: 'c1', building: 'barracks' }), { plot: 'c1' });
    const { state, refund } = demolish(data, v, 'c1', at(v), 1);
    const barracks = data.buildings.buildings.barracks!;
    expect(refund.wood).toBe(Math.floor((levelCost(barracks, 1).wood + levelCost(barracks, 2).wood) / 2));
    expect(state.plots.c1).toEqual({ building: null, level: 0 });
    expect(state.levels.barracks).toBeUndefined();
    expect(() => demolish(data, v, HALL_PLOT, at(v), 1)).toThrow(/Elder's Hall/);
    expect(() => demolish(data, build(v, { plot: 'f0' }), 'f0', at(v), 1)).toThrow("The Woodcutter can't be torn down");
  });

  it('trades at the market, better with every level', () => {
    const v = build(rich(newVillage(data, T0, 1)), { plot: 'c1', building: 'market' });
    const { state, got } = trade(data, v, { give: 'wood', get: 'iron', amount: 100 }, at(v));
    expect(got).toBe(40);
    expect(amountsAt(state.ledger, at(v)).wood).toBe(amountsAt(v.ledger, at(v)).wood - 100);
    const bigger = build(v, { plot: 'c1' });
    expect(trade(data, bigger, { give: 'wood', get: 'iron', amount: 100 }, at(bigger)).got).toBe(44);
    expect(() => trade(data, rich(newVillage(data, T0, 1)), { give: 'wood', get: 'iron', amount: 100 }, T0)).toThrow(/Build a Market/);
  });

  it('saves some of the fallen in the hospital, as its chance says', () => {
    const always = () => 0;
    const never = () => 0.99;
    expect(hospitalHealed({ hospital: 0.1 }, { spearman: 3, archer: 2 }, always)).toEqual({ archer: 2, spearman: 3 });
    expect(hospitalHealed({ hospital: 0.1 }, { spearman: 3 }, never)).toEqual({});
    expect(hospitalHealed({}, { spearman: 3 }, always)).toEqual({});
  });
});
