import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { hex, hexDistance, hexKey } from '../src/sim/hex.js';
import { frontOf, generateMap } from '../src/sim/mapgen.js';
import {
  composeWave,
  marchSpeed,
  planMarch,
  planWave,
  raidsAlong,
  spawnTime,
  threatOf,
  waveFronts,
  waveSize,
  type WaveContext,
} from '../src/sim/waves.js';

const data = loadGameData();
const T0 = new Date('2026-03-01T00:00:00Z');
const HOUR = 3_600_000;
const ctx: WaveContext = { seed: 4242, activeFronts: ['north', 'south', 'east'], playerCount: 2, startedAt: T0, worldSpeed: 1 };

describe('wave schedule', () => {
  it('only uses fronts that are both enabled and active', () => {
    expect(waveFronts(data, ['north', 'south'])).toEqual(['north', 'south']);
    expect(waveFronts(data, ['west', 'north', 'east', 'south'])).toEqual(['north', 'east', 'south', 'west']);
    const northOnly = { ...data, waves: { ...data.waves, enabledFronts: ['north' as const] } };
    expect(waveFronts(northOnly, ['north', 'south'])).toEqual(['north']);
    expect(() => waveFronts(northOnly, ['south'])).toThrow();
  });

  it('starts after the grace period, then every 2-3 days', () => {
    const first = spawnTime(data, ctx, 0, null);
    expect(first.getTime() - T0.getTime()).toBe(data.waves.graceHours * HOUR);
    let previous = first;
    for (let index = 1; index < 10; index++) {
      const next = spawnTime(data, ctx, index, previous);
      const gap = (next.getTime() - previous.getTime()) / HOUR;
      expect(gap).toBeGreaterThanOrEqual(48);
      expect(gap).toBeLessThanOrEqual(72);
      previous = next;
    }
  });

  it('world speed compresses the schedule', () => {
    expect(spawnTime(data, { ...ctx, worldSpeed: 10 }, 0, null).getTime() - T0.getTime()).toBe(
      (data.waves.graceHours * HOUR) / 10,
    );
  });

  it('grows with each wave and with more players', () => {
    expect(waveSize(data, 0, 1)).toBe(data.waves.baseUnits);
    expect(waveSize(data, 4, 1)).toBeGreaterThan(waveSize(data, 3, 1));
    expect(waveSize(data, 0, 4)).toBeGreaterThan(waveSize(data, 0, 1));
  });

  it('composes exactly the wave size from eligible units', () => {
    for (const index of [0, 2, 5, 9]) {
      const size = waveSize(data, index, 3);
      const composition = composeWave(data, 'north', index, size, 99);
      expect(Object.values(composition).reduce((a, b) => a + b, 0)).toBe(size);
      for (const unit of Object.keys(composition)) {
        const def = data.enemies.fronts.north!.units[unit]!;
        expect(def.tier ? data.enemies.tiers.minWave[def.tier - 1]! : def.minWave).toBeLessThanOrEqual(index);
      }
    }
    expect(composeWave(data, 'north', 0, 50, 1).likho).toBeUndefined();
  });

  it('brings in troops by tier, the older tiers fading as newer ones join', () => {
    const tiers = data.enemies.tiers.minWave;
    for (const front of ['north', 'east', 'south', 'west'] as const) {
      const units = Object.values(data.enemies.fronts[front]!.units).filter((u) => u.tier);
      // An infantry, an archer and a cavalry unit in each of four tiers.
      for (const tier of [1, 2, 3, 4]) {
        expect(units.filter((u) => u.tier === tier).map((u) => u.family).sort()).toEqual(['archers', 'cavalry', 'infantry']);
      }
    }
    const tierOf = (unit: string) => data.enemies.fronts.east!.units[unit]!.tier ?? 0;
    const share = (index: number, tier: number) => {
      const wave = composeWave(data, 'east', index, 1000, 7);
      return Object.entries(wave).filter(([unit]) => tierOf(unit) === tier).reduce((sum, [, n]) => sum + n, 0) / 1000;
    };
    expect(share(tiers[1]! - 1, 2)).toBe(0);
    expect(share(tiers[1]!, 2)).toBeGreaterThan(0);
    expect(share(tiers[3]!, 1)).toBeLessThan(share(tiers[1]! - 1, 1) / 4);
    expect(share(tiers[3]!, 4)).toBeGreaterThan(0.2);
  });

  it('gives every front its own roster, some units only for bigger groups', () => {
    for (const front of ['north', 'east', 'south', 'west'] as const) {
      const roster = data.enemies.fronts[front]!;
      const composition = composeWave(data, front, 9, 200, 5, 6);
      expect(Object.keys(composition).every((unit) => unit in roster.units)).toBe(true);
      expect(roster.personality.nerve).toBeGreaterThan(0);
    }
    // The zmey and the Order's southern siege rams wait for groups of three.
    expect(composeWave(data, 'north', 10, 500, 5, 2).zmey_whelp).toBeUndefined();
    expect(composeWave(data, 'north', 10, 500, 5, 3).zmey_whelp).toBeGreaterThan(0);
    expect(composeWave(data, 'south', 9, 500, 5, 1).siege_ram).toBeUndefined();
    // Nomads ride: their slowest unit outpaces the Order's.
    expect(marchSpeed(data, 'east', composeWave(data, 'east', 9, 200, 5, 6))).toBeGreaterThan(
      marchSpeed(data, 'south', composeWave(data, 'south', 9, 200, 5, 6)),
    );
  });

  it('rotates the active fronts', () => {
    const fronts = [0, 1, 2, 3, 4].map((index) => planWave(data, { ...ctx, activeFronts: ['north', 'east', 'south', 'west'] }, index, T0).front);
    expect(fronts).toEqual(['north', 'east', 'south', 'west', 'north']);
  });

  it('labels threat by size', () => {
    expect(threatOf(data, { grey_wolf: 8 })).toBe('Low');
    expect(threatOf(data, { grey_wolf: 20 })).toBe('Moderate');
    expect(threatOf(data, { grey_wolf: 500 })).toBe('Severe');
  });

  it('is deterministic for a seed and index', () => {
    expect(planWave(data, ctx, 3, T0)).toEqual(planWave(data, ctx, 3, T0));
    expect(planWave(data, ctx, 3, T0).composition).not.toEqual(planWave(data, { ...ctx, seed: 7 }, 3, T0).composition);
  });
});

describe('wave march', () => {
  const map = generateMap(data, 2026, 2);
  const villages = map.startSites.map((site, i) => ({ id: i + 1, q: site.q, r: site.r }));
  const wave = planWave(data, ctx, 0, null);
  const march = planMarch(data, {
    terrain: map.terrain,
    radius: map.radius,
    wave,
    villages,
    seed: ctx.seed,
    departAt: wave.spawnAt,
    worldSpeed: 1,
  });

  it('marches from every active front of a full map', () => {
    const big = generateMap(data, 2026, 4);
    const sites = big.startSites.map((site, i) => ({ id: i + 1, q: site.q, r: site.r }));
    for (const [index, front] of (['north', 'east', 'south', 'west'] as const).entries()) {
      const planned = planWave(data, { ...ctx, activeFronts: big.activeFronts, playerCount: 4 }, index, T0);
      expect(planned.front).toBe(front);
      const m = planMarch(data, { terrain: big.terrain, radius: big.radius, wave: planned, villages: sites, seed: 2026, departAt: T0, worldSpeed: 1 });
      expect(frontOf(m.spawn)).toBe(front);
      expect(data.enemies.fronts[front]!.spawnTerrain).toContain(big.terrain.get(hexKey(m.spawn)));
    }
  });

  it('spawns in the north spawn zone', () => {
    expect(frontOf(march.spawn)).toBe('north');
    expect(data.enemies.fronts.north!.spawnTerrain).toContain(map.terrain.get(hexKey(march.spawn)));
    expect(march.path[0]).toMatchObject({ q: march.spawn.q, r: march.spawn.r, atMs: 0 });
  });

  it('marches hex by hex to a village', () => {
    const target = villages.find((v) => v.id === march.targetVillageId)!;
    expect(target).toBeDefined();
    expect(march.path.at(-1)).toMatchObject({ q: target.q, r: target.r });
    for (let i = 1; i < march.path.length; i++) {
      const [a, b] = [march.path[i - 1]!, march.path[i]!];
      expect(hexDistance(hex(a.q, a.r), hex(b.q, b.r))).toBe(1);
      expect(b.atMs).toBeGreaterThan(a.atMs);
    }
    expect(march.arrivesAt.getTime()).toBe(wave.spawnAt.getTime() + march.path.at(-1)!.atMs);
  });

  it('moves at the pace of its slowest unit over the terrain', () => {
    const step = march.path[1]!;
    const cost = data.terrain.terrain[map.terrain.get(hexKey(hex(step.q, step.r)))!].moveCost!;
    expect(step.atMs).toBe(Math.round((cost / marchSpeed(data, 'north', wave.composition)) * HOUR));
  });

  it('heads for the Holy City when there are no villages', () => {
    const empty = planMarch(data, {
      terrain: map.terrain,
      radius: map.radius,
      wave,
      villages: [],
      seed: ctx.seed,
      departAt: wave.spawnAt,
      worldSpeed: 1,
    });
    expect(empty.targetVillageId).toBeNull();
    expect(empty.path.at(-1)).toMatchObject({ q: 0, r: 0 });
  });
});

describe('outpost raids', () => {
  const path = [
    { q: 0, r: -6, atMs: 0 },
    { q: 0, r: -5, atMs: 1000 },
    { q: 0, r: -4, atMs: 2000 },
    { q: 1, r: -4, atMs: 3000 },
  ];
  const outpost = (q: number, r: number) => ({ villageId: 7, plot: `o${q},${r}`, cell: hex(q, r) });

  it('hits outposts within reach of the route when the horde first comes close', () => {
    const raids = raidsAlong(path, [outpost(1, -6), outpost(2, -4), outpost(3, -4), outpost(0, -4)], 1);
    expect(raids.map((r) => [r.plot, r.atMs])).toEqual([
      ['o1,-6', 0],
      ['o2,-4', 3000],
      ['o0,-4', 1000],
    ]);
    expect(raidsAlong(path, [outpost(3, -4)], 2)).toHaveLength(1);
    expect(raidsAlong(path, [outpost(1, -6)], 0)).toHaveLength(0);
  });

  it('ignores the part of the route already behind the horde', () => {
    expect(raidsAlong(path, [outpost(1, -6)], 1, 500)).toEqual([{ ...outpost(1, -6), atMs: 1000 }]);
    expect(raidsAlong(path, [outpost(1, -6)], 1, 1500)).toEqual([]);
  });
});
