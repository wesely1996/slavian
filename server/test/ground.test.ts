// The ground a battle is fought on (battle.json terrain, sim/ground.ts).
import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { clanBonuses } from '../src/sim/clans.js';
import { battleRng, playerStats, resolveRound } from '../src/sim/battle.js';
import { groundAt, groundFactors } from '../src/sim/ground.js';
import { hex, hexKey, neighbors } from '../src/sim/hex.js';
import { edgeKey } from '../src/sim/land.js';

const data = loadGameData();
const centre = hex(0, 0);

function map(own: TerrainId, around: TerrainId[] = []): Map<string, TerrainId> {
  const terrain = new Map<string, TerrainId>([[hexKey(centre), own]]);
  neighbors(centre).forEach((n, i) => terrain.set(hexKey(n), around[i] ?? 'plains'));
  return terrain;
}

describe('ground', () => {
  it('reads the hex, the mountains beside it and the waters along it', () => {
    const ring = neighbors(centre);
    const rivers = new Set([edgeKey(centre, ring[3]!)]);
    expect(groundAt(data, map('wooded_hills', ['mountain', 'mountain', 'mountain', 'plains', 'lake']), rivers, centre)).toEqual({
      woods: 1,
      hills: 1,
      mountain: 3,
      water: 2,
    });
    expect(groundAt(data, map('plains'), new Set(), centre)).toEqual({ flat: 1 });
  });

  it('gives each family its strength there, mountains and waters counted at most twice', () => {
    expect(groundFactors(data, { flat: 1 }, 'cavalry', undefined).attack).toBeCloseTo(1.3);
    expect(groundFactors(data, { woods: 1 }, 'archers', undefined).attack).toBeCloseTo(0.8);
    expect(groundFactors(data, { hills: 1, mountain: 3 }, 'archers', undefined).attack).toBeCloseTo(1.5);
    expect(groundFactors(data, { hills: 1 }, 'infantry', undefined)).toEqual({ attack: 1.2, defense: 1 });
    expect(groundFactors(data, undefined, 'cavalry', undefined)).toEqual({ attack: 1, defense: 1 });
  });

  it("adds a unit's own and its clan's shares", () => {
    // Rod Zmije holds the wetlands; its serpent axemen strike hard there.
    const stats = playerStats(data, clanBonuses(data, 'zmija'))('serpent_axeman');
    expect(groundFactors(data, { wetland: 1, water: 3 }, stats.family, stats.terrain)).toEqual({ attack: 1.2, defense: 1.4 });
    // A forest archer shoots as well in the woods as elsewhere.
    const archer = playerStats(data)('forest_archer');
    expect(groundFactors(data, { woods: 1 }, archer.family, archer.terrain).attack).toBeCloseTo(1);
  });

  it('makes horsemen deadlier on open ground', () => {
    const fight = (ground: Record<string, number> | undefined) =>
      resolveRound(
        data,
        { units: { horseman: 40 }, stance: 'balanced', stats: playerStats(data), home: false },
        { units: { axe_levy: 200 }, stance: 'balanced', stats: playerStats(data), home: false },
        battleRng(1, 1, 1),
        undefined,
        ground,
      ).defenderLosses.axe_levy ?? 0;
    expect(fight({ flat: 1 })).toBeGreaterThan(fight({ woods: 1 }));
  });
});
