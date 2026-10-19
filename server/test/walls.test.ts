import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { RuleError } from '../src/errors.js';
import { createRng } from '../src/sim/rng.js';
import { breachWalls, initialPlots, newVillage, queueBuild, type Plot } from '../src/sim/village.js';
import {
  ballistaKills,
  openTowerSlots,
  siegeDamage,
  siegePower,
  siegeWorks,
  wallFactors,
  wallIntegrity,
  wallTier,
  warningHours,
} from '../src/sim/walls.js';

const data = loadGameData();
const at = new Date('2030-01-01T00:00:00Z');

function walled(level: number, towers: Record<string, number> = {}): Record<string, Plot> {
  const plots = initialPlots(data);
  plots.w = { building: 'wall', level };
  Object.entries(towers).forEach(([tower, l], i) => (plots[`t${i}`] = { building: tower, level: l }));
  return plots;
}

describe('walls', () => {
  it('are laid out unbuilt, with their slots', () => {
    const plots = initialPlots(data);
    expect(plots.w).toEqual({ building: 'wall', level: 0 });
    expect(Object.keys(plots).filter((id) => /^t\d$/.test(id))).toHaveLength(data.walls.slotsAt.length);
    expect(wallIntegrity(data, plots)).toBe(0);
  });

  it('rise through tiers and open wall slots', () => {
    expect(wallTier(data, 0)).toBeNull();
    expect(wallTier(data, 1)).toBe('Palisade');
    expect(wallTier(data, 5)).toBe('Stone Wall');
    expect(wallTier(data, 10)).toBe('Fortress Walls');
    expect(openTowerSlots(data, 0)).toBe(0);
    expect(openTowerSlots(data, 1)).toBe(1);
    expect(openTowerSlots(data, 4)).toBe(2);
    expect(openTowerSlots(data, 10)).toBe(5);
  });

  it('toughen the garrison while they stand, with their towers', () => {
    const plots = walled(5, { gate_tower: 2, archer_tower: 3, murder_holes: 1 });
    expect(wallIntegrity(data, plots)).toBe(Math.round(120 * 5 * 1.16));
    const f = wallFactors(data, plots);
    expect(f.defense).toBeCloseTo(1 + 5 * 0.03 + 0.04);
    expect(f.attack).toBeCloseTo(1.15);
    expect(warningHours(data, walled(3, { watchtower: 2 }))).toBe(2);
  });

  it('are battered by siege, less behind a ditch', () => {
    expect(siegePower(data, 'south', { siege_ram: 2, zealot: 10 })).toBeCloseTo(80 + 10 * data.enemies.fronts.south!.units.zealot!.attack * 0.02);
    const ditch = walled(4, { ditch: 4 });
    expect(siegeDamage(data, 'south', { siege_ram: 1 }, ditch)).toBeCloseTo(40 * 0.8);
  });

  it('make a horde build engines first, by its craft', () => {
    const plots = walled(6);
    const integrity = wallIntegrity(data, plots);
    const order = siegeWorks(data, 'south', { zealot: 20 }, integrity, plots, 1)!;
    expect(order.engine).toBe('siege_ram');
    expect(order.count).toBeGreaterThan(0);
    expect(order.setupMs).toBe(Math.round(3 * 0.8 * 3_600_000));
    const nomads = siegeWorks(data, 'east', { steppe_raider: 20 }, integrity, plots, 1)!;
    expect(nomads.engine).toBe('scaling_ladders');
    expect(nomads.setupMs).toBeGreaterThan(order.setupMs);
    // Monsters build nothing; a horde with rams enough builds nothing.
    expect(siegeWorks(data, 'north', { grey_wolf: 30 }, integrity, plots, 1)).toBeNull();
    expect(siegeWorks(data, 'south', { siege_ram: 10 }, integrity, plots, 1)).toBeNull();
  });

  it('smash engines with ballistae, the biggest first', () => {
    const plots = walled(5, { ballista: 6 });
    const kills = ballistaKills(data, 'south', { catapult: 1, siege_ram: 3, zealot: 9 }, plots, createRng(1));
    expect(kills.catapult).toBe(1);
    expect((kills.siege_ram ?? 0) + 1).toBeGreaterThanOrEqual(2);
    expect(kills.zealot).toBeUndefined();
    expect(ballistaKills(data, 'south', { siege_ram: 3 }, walled(5), createRng(1))).toEqual({});
  });

  it('fall a level when breached', () => {
    const state = { ...newVillage(data, at, 1), plots: walled(4) };
    expect(breachWalls(data, state).plots.w!.level).toBe(3);
    expect(breachWalls(data, { ...state, plots: walled(0) }).plots.w!.level).toBe(0);
  });

  it('are built on their plot, towers only in open wall slots', () => {
    const fresh = newVillage(data, at, 1);
    const rich = { ...fresh, ledger: { ...fresh.ledger, amounts: { wood: 1e6, stone: 1e6, grain: 1e6, iron: 1e6 }, capacity: { wood: 2e6, stone: 2e6, grain: 2e6, iron: 2e6 } } };
    const queued = queueBuild(data, rich, { building: 'wall' }, at, 1);
    expect(queued.queued.plot).toBe('w');
    expect(() => queueBuild(data, rich, { plot: 't0', building: 'archer_tower' }, at, 1)).toThrow(/not open yet/);
    const withWall = { ...rich, plots: walled(1), levels: { ...rich.levels, wall: 1 } };
    expect(queueBuild(data, withWall, { building: 'archer_tower' }, at, 1).queued.plot).toBe('t0');
    expect(() => queueBuild(data, withWall, { plot: 't0', building: 'barracks' }, at, 1)).toThrow(RuleError);
    expect(() => queueBuild(data, withWall, { plot: 'c1', building: 'archer_tower' }, at, 1)).toThrow(/wall slot/);
  });
});
