import { describe, expect, it } from 'vitest';
import { loadGameData, type TerrainId } from '../src/data/index.js';
import { isChokePoint, setupAt, setupFactors, stepInto } from '../src/sim/field.js';
import { hex, hexKey, neighbors } from '../src/sim/hex.js';

const data = loadGameData();

function ground(center: TerrainId, blocked: number): Map<string, TerrainId> {
  const terrain = new Map<string, TerrainId>([[hexKey(hex(0, 0)), center]]);
  neighbors(hex(0, 0)).forEach((n, i) => terrain.set(hexKey(n), i < blocked ? 'mountain' : 'plains'));
  return terrain;
}

describe('field battles', () => {
  it('find choke points between mountains and lakes', () => {
    const need = data.field.choke.minBlockedNeighbors;
    expect(isChokePoint(data, ground('plains', need), hex(0, 0))).toBe(true);
    expect(isChokePoint(data, ground('plains', need - 1), hex(0, 0))).toBe(false);
    expect(isChokePoint(data, ground('mountain', 6), hex(0, 0))).toBe(false);
  });

  it('give an ambush to holders on cover who got there in time', () => {
    const prepMs = (data.field.ambush.prepMinutes * 60_000) / 10;
    const at = new Date('2026-05-01T12:00:00Z');
    const setup = (center: TerrainId, readyMsBefore: number, fort = false) =>
      setupAt(data, { terrain: ground(center, 0), cell: hex(0, 0), readySince: new Date(at.getTime() - readyMsBefore), hordeArrives: at, worldSpeed: 10, fort });
    expect(setup('forest', prepMs)).toEqual({ ambush: true, choke: false, fort: false });
    expect(setup('forest', prepMs - 1).ambush).toBe(false);
    expect(setup('plains', prepMs * 2).ambush).toBe(false);
    expect(setup('plains', 0, true).fort).toBe(true);
  });

  it('turn the setup into round multipliers', () => {
    const { ambush, choke, fort } = data.field;
    const all = { ambush: true, choke: true, fort: true };
    expect(setupFactors(data, all, { round: 1, holdersStance: 'hold_the_line' })).toEqual({
      holderAttack: 1 + ambush.bonus,
      holderDefense: 1 + fort.defenseBonus + choke.holdTheLineDefense,
      hordeAttack: choke.attackerFactor,
      hordeStanceless: true,
    });
    // The surprise lasts one round; the choke only helps a line that holds.
    expect(setupFactors(data, all, { round: 2, holdersStance: 'balanced' })).toEqual({
      holderAttack: 1,
      holderDefense: 1 + fort.defenseBonus,
      hordeAttack: choke.attackerFactor,
      hordeStanceless: false,
    });
    expect(setupFactors(data, { ambush: false, choke: false, fort: false }, { round: 1, holdersStance: 'balanced' })).toEqual({
      holderAttack: 1,
      holderDefense: 1,
      hordeAttack: 1,
      hordeStanceless: false,
    });
  });

  it('find where a road enters a hex', () => {
    const path = [
      { q: 0, r: 0, atMs: 0 },
      { q: 1, r: 0, atMs: 100 },
      { q: 2, r: 0, atMs: 200 },
    ];
    expect(stepInto(path, hex(1, 0))).toEqual({ q: 1, r: 0, atMs: 100 });
    expect(stepInto(path, hex(1, 0), 101)).toBeNull();
    expect(stepInto(path, hex(5, 5))).toBeNull();
  });
});
