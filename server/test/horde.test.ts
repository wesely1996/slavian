import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import {
  campSite,
  decideRaze,
  holyCityGuard,
  rebuildCost,
  recruit,
  refugeeSite,
  ruinPlots,
  sanctityDamage,
  type RazeInput,
} from '../src/sim/horde.js';
import { hex, hexKey, spiral } from '../src/sim/hex.js';
import { initialPlots, levelCost } from '../src/sim/village.js';
import { routeFrom, targetsOf } from '../src/sim/waves.js';

const data = loadGameData();
const HOUR = 3_600_000;

function plains(radius: number): Map<string, TerrainId> {
  return new Map(spiral(hex(0, 0), radius).map((c) => [hexKey(c), (c.q === 0 && c.r === 0 ? 'holy_city' : 'plains') as TerrainId]));
}

describe('raid or raze', () => {
  const base: RazeInput = {
    front: 'south',
    waveIndex: 5,
    hordeNow: 60,
    hordeInitial: 80,
    helpNearby: 10,
    rampageLeftMs: 10 * HOUR,
    worldSpeed: 1,
  };

  it('razes with time, strength and a faction that burns', () => {
    expect(decideRaze(data, base).choice).toBe('raze');
  });

  it('only raids in the first waves, at refugee camps, without time or against help', () => {
    expect(decideRaze(data, { ...base, waveIndex: 0 })).toEqual({ choice: 'raid', reasons: ['an early raiding party'] });
    expect(decideRaze(data, { ...base, refuge: true }).choice).toBe('raid');
    expect(decideRaze(data, { ...base, rampageLeftMs: data.horde.raze.hours * HOUR - 1 })).toEqual({ choice: 'raid', reasons: ['no time to raze'] });
    expect(decideRaze(data, { ...base, helpNearby: 50 })).toEqual({ choice: 'raid', reasons: ['help is near'] });
  });

  it('weighs the faction and how battered the horde is', () => {
    // Nomads would rather plunder; a horde under half strength thinks twice.
    expect(decideRaze(data, { ...base, front: 'east' }).choice).toBe('raid');
    expect(decideRaze(data, { ...base, front: 'north', hordeNow: 25, helpNearby: 16 }).choice).toBe('raid');
    expect(decideRaze(data, { ...base, front: 'north', hordeNow: 40, hordeInitial: 40, helpNearby: 10 }).choice).toBe('raze');
  });

  it('recruits after a raid', () => {
    expect(recruit(data, { zealot: 40, crossbowman: 5 }, { zealot: 10 })).toEqual({ zealot: 14 });
  });
});

describe('ruins', () => {
  it('burn everything to level 0 and rebuild at a share of its cost', () => {
    const plots = { ...initialPlots(data), f0: { building: data.buildings.village.fields[0]!, level: 2 } };
    const ruined = ruinPlots(plots);
    expect(Object.values(ruined).every((p) => p.level === 0)).toBe(true);
    const field = data.buildings.buildings[plots.f0.building]!;
    const hall = data.buildings.buildings.elder_hall!;
    const full = ['wood', 'stone', 'grain', 'iron'].map(
      (k) => levelCost(field, 1)[k as 'wood'] + levelCost(field, 2)[k as 'wood'] + levelCost(hall, 1)[k as 'wood'],
    );
    expect(Object.values(rebuildCost(data, plots))).toEqual(full.map((n) => Math.round(n * data.horde.ruins.rebuildCostShare)));
  });

  it('find a camp site next to the horde and a refuge by the Holy City', () => {
    const terrain = plains(5);
    const taken = new Set([hexKey(hex(3, 0)), ...spiral(hex(3, 0), 1).map(hexKey).slice(0, 3)]);
    const site = campSite(data, terrain, hex(3, 0), taken)!;
    expect(taken.has(hexKey(site))).toBe(false);
    const refuge = refugeeSite(data, terrain, new Set())!;
    expect(Math.max(Math.abs(refuge.q), Math.abs(refuge.r), Math.abs(refuge.q + refuge.r))).toBe(data.horde.refugeeCamp.minDistance);
    expect(refugeeSite(data, new Map([[hexKey(hex(0, 0)), 'holy_city']]), new Set())).toBeNull();
  });
});

describe('the Holy City', () => {
  it('has a guard that grows each wave and loses Sanctity to survivors', () => {
    expect(holyCityGuard(data, 0)).toEqual(data.horde.holyCity.guard);
    expect(holyCityGuard(data, 5).spearman!).toBeGreaterThan(data.horde.holyCity.guard.spearman!);
    expect(sanctityDamage(data, 9)).toBe(Math.ceil(9 * data.horde.holyCity.damagePerUnit));
  });
});

describe('targeting', () => {
  const terrain = plains(6);
  const route = (fear?: Map<string, number>, villages = [{ id: 1, q: 2, r: -4 }, { id: 2, q: -2, r: -2 }]) =>
    routeFrom(data, {
      terrain,
      from: hex(0, -6),
      targets: targetsOf(villages),
      front: 'south',
      composition: { zealot: 10 },
      ...(fear ? { fear } : {}),
      rng: () => 0,
      startMs: 1000,
      worldSpeed: 1,
    })!;

  it('takes the cheapest village, avoiding feared ones', () => {
    const plain = route();
    expect(plain.path[0]).toMatchObject({ q: 0, r: -6, atMs: 1000 });
    const first = plain.targetVillageId;
    const feared = new Map([[hexKey(first === 1 ? hex(2, -4) : hex(-2, -2)), 50]]);
    expect(route(feared).targetVillageId).toBe(first === 1 ? 2 : 1);
  });

  it('goes for the Holy City when no village is closer, or there is nothing else', () => {
    expect(route(undefined, []).targetVillageId).toBeNull();
    expect(route(undefined, [{ id: 3, q: 0, r: 6 }]).targetVillageId).toBeNull();
    // As close as the Holy City: the village.
    expect(route(undefined, [{ id: 4, q: 6, r: -6 }]).targetVillageId).toBe(4);
  });
});
