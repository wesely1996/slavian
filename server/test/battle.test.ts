import { describe, expect, it } from 'vitest';
import { loadGameData, type Stance } from '../src/data/index.js';
import {
  battleOutcome,
  battleRng,
  enemyStats,
  playerStats,
  raidLoot,
  resolveRound,
  subtractUnits,
  total,
  waveStance,
  type Outcome,
  type Side,
} from '../src/sim/battle.js';

const data = loadGameData();
const players = playerStats(data);
const monsters = enemyStats(data, 'north');

const horde = (units: Record<string, number>, stance: Stance = 'balanced'): Side => ({ units, stance, stats: monsters, home: false });
const garrison = (units: Record<string, number>, stance: Stance = 'balanced'): Side => ({ units, stance, stats: players, home: true });

// Average kills over many seeded rounds, to compare setups without noise.
function averageKills(attacker: Side, defender: Side, rounds = 400): { attackerLosses: number; defenderLosses: number } {
  let a = 0;
  let d = 0;
  for (let i = 0; i < rounds; i++) {
    const r = resolveRound(data, attacker, defender, battleRng(1, i, 1));
    a += total(r.attackerLosses);
    d += total(r.defenderLosses);
  }
  return { attackerLosses: a / rounds, defenderLosses: d / rounds };
}

function fight(attacker: Side, defender: Side, battleId = 1): { outcome: Outcome; rounds: number; attackerLeft: number; defenderLeft: number } {
  let a = attacker.units;
  let d = defender.units;
  for (let round = 1; ; round++) {
    const r = resolveRound(data, { ...attacker, units: a }, { ...defender, units: d }, battleRng(42, battleId, round));
    a = subtractUnits(a, r.attackerLosses);
    d = subtractUnits(d, r.defenderLosses);
    const outcome = battleOutcome(data, {
      round,
      attackerStance: attacker.stance,
      attackerInitial: attacker.units,
      attackerNow: a,
      defenderStance: defender.stance,
      defenderInitial: defender.units,
      defenderNow: d,
    });
    if (outcome !== 'ongoing') return { outcome, rounds: round, attackerLeft: total(a), defenderLeft: total(d) };
  }
}

describe('a battle round', () => {
  it('is deterministic for a seed', () => {
    const a = horde({ grey_wolf: 10 });
    const d = garrison({ spearman: 10 });
    expect(resolveRound(data, a, d, battleRng(5, 1, 1))).toEqual(resolveRound(data, a, d, battleRng(5, 1, 1)));
  });

  it('never kills more than are there', () => {
    const r = resolveRound(data, horde({ cave_bear: 200 }), garrison({ scout: 3 }), battleRng(1, 1, 1));
    expect(r.defenderLosses.scout).toBe(3);
  });

  it('applies counters: spears beat cavalry (wolves), archers beat infantry (thralls)', () => {
    // Kills × target defense measures damage dealt; the counter adds 50%.
    const wolfDefense = data.enemies.fronts.north!.units.grey_wolf!.defense;
    const thrallDefense = data.enemies.fronts.north!.units.leshy_thrall!.defense;
    const damage = (units: Record<string, number>, target: string, defense: number) =>
      averageKills(horde({ [target]: 200 }), garrison(units)).attackerLosses * defense;

    const spearRatio = damage({ spearman: 20 }, 'grey_wolf', wolfDefense) / damage({ spearman: 20 }, 'leshy_thrall', thrallDefense);
    expect(spearRatio).toBeCloseTo(1.5, 1);
    const archerRatio = damage({ archer: 20 }, 'leshy_thrall', thrallDefense) / damage({ archer: 20 }, 'grey_wolf', wolfDefense);
    expect(archerRatio).toBeCloseTo(1.5, 1);
  });

  it('stances trade attack for defense', () => {
    const balanced = averageKills(horde({ leshy_thrall: 20 }), garrison({ spearman: 20 }, 'balanced'));
    const offensive = averageKills(horde({ leshy_thrall: 20 }), garrison({ spearman: 20 }, 'offensive'));
    const defensive = averageKills(horde({ leshy_thrall: 20 }), garrison({ spearman: 20 }, 'defensive'));
    expect(offensive.attackerLosses).toBeGreaterThan(balanced.attackerLosses);
    expect(defensive.defenderLosses).toBeLessThan(balanced.defenderLosses);
  });

  it('fighting at home makes defenders tougher', () => {
    const home = averageKills(horde({ leshy_thrall: 20 }), garrison({ spearman: 20 }));
    const field = averageKills(horde({ leshy_thrall: 20 }), { ...garrison({ spearman: 20 }), home: false });
    expect(home.defenderLosses).toBeLessThan(field.defenderLosses);
  });
});

describe('battle outcome', () => {
  const base = {
    round: 1,
    attackerStance: 'balanced' as Stance,
    attackerInitial: { grey_wolf: 10 },
    defenderStance: 'balanced' as Stance,
    defenderInitial: { spearman: 10 },
  };

  it('ends when a side is wiped out, the defenders holding if both fall', () => {
    expect(battleOutcome(data, { ...base, attackerNow: {}, defenderNow: { spearman: 3 } })).toBe('defended');
    expect(battleOutcome(data, { ...base, attackerNow: { grey_wolf: 3 }, defenderNow: {} })).toBe('raided');
    expect(battleOutcome(data, { ...base, attackerNow: {}, defenderNow: {} })).toBe('defended');
  });

  it('ends when a side has lost its stance retreat share', () => {
    // Balanced breaks at 60% losses.
    expect(battleOutcome(data, { ...base, attackerNow: { grey_wolf: 5 }, defenderNow: { spearman: 10 } })).toBe('ongoing');
    expect(battleOutcome(data, { ...base, attackerNow: { grey_wolf: 4 }, defenderNow: { spearman: 10 } })).toBe('defended');
    expect(battleOutcome(data, { ...base, attackerNow: { grey_wolf: 10 }, defenderNow: { spearman: 4 } })).toBe('raided');
  });

  it('hold the line never breaks', () => {
    expect(
      battleOutcome(data, { ...base, defenderStance: 'hold_the_line', attackerNow: { grey_wolf: 10 }, defenderNow: { spearman: 1 } }),
    ).toBe('ongoing');
  });

  it('the horde withdraws when the last round passes undecided', () => {
    expect(
      battleOutcome(data, { ...base, round: data.battle.maxRounds, attackerNow: { grey_wolf: 9 }, defenderNow: { spearman: 9 } }),
    ).toBe('defended');
  });
});

describe('whole battles', () => {
  it('a solid garrison holds against the first wave', () => {
    const result = fight(horde({ grey_wolf: 5, leshy_thrall: 3 }), garrison({ spearman: 15 }));
    expect(result.outcome).toBe('defended');
    expect(result.defenderLeft).toBeGreaterThan(10);
  });

  it('a token garrison is overrun', () => {
    expect(fight(horde({ grey_wolf: 14, leshy_thrall: 7, cave_bear: 4 }), garrison({ spearman: 2 })).outcome).toBe('raided');
  });

  it('battles last several rounds, not one', () => {
    const result = fight(horde({ grey_wolf: 10, leshy_thrall: 6 }), garrison({ spearman: 10, archer: 6 }));
    expect(result.rounds).toBeGreaterThan(1);
  });
});

describe('raids and stances', () => {
  it('loot shrinks with the horde', () => {
    const stores = { wood: 1000, stone: 500, grain: 100, iron: 0 };
    expect(raidLoot(data, stores, { grey_wolf: 10 }, { grey_wolf: 10 })).toEqual({ wood: 300, stone: 150, grain: 30, iron: 0 });
    expect(raidLoot(data, stores, { grey_wolf: 10 }, { grey_wolf: 5 })).toEqual({ wood: 150, stone: 75, grain: 15, iron: 0 });
  });

  it('wave stances follow the front temperament', () => {
    const counts: Record<string, number> = {};
    for (let index = 0; index < 1000; index++) {
      const stance = waveStance(data, 'north', 9, index);
      counts[stance] = (counts[stance] ?? 0) + 1;
    }
    expect(counts.offensive).toBeGreaterThan(counts.balanced!);
    expect(counts.balanced).toBeGreaterThan(counts.defensive!);
    expect(waveStance(data, 'north', 9, 3)).toBe(waveStance(data, 'north', 9, 3));
  });
});
