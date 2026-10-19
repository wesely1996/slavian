import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { enemyStats } from '../src/sim/battle.js';
import {
  gainLeaderXp,
  leaderAfterBattle,
  leaderEffects,
  leaderTitle,
  leaderXpToNext,
  ledStats,
  newLeader,
  riseLevel,
} from '../src/sim/leaders.js';

const data = loadGameData();

describe('enemy leaders', () => {
  it('are named from their front, never twice while names last', () => {
    const first = newLeader(data, 'east', 7, []);
    expect(data.leaders.fronts.east!.names).toContain(first.name);
    expect(first).toMatchObject({ level: 1, xp: 0, skills: {} });
    const second = newLeader(data, 'east', 7, [first.name]);
    expect(second.name).not.toBe(first.name);
    expect(leaderTitle(data, 'east', first)).toBe(`Beg ${first.name}`);
    expect(leaderTitle(data, 'east', { name: first.name, level: 5 })).toBe(`Khan ${first.name}`);
    expect(leaderTitle(data, 'north', { name: 'Mara', level: 12 })).toBe('Mara the Deathless');
  });

  it('level up from experience and take their front’s skills in order', () => {
    const start = newLeader(data, 'north', 1, []);
    const once = gainLeaderXp(data, 'north', start, leaderXpToNext(data, 1));
    expect(once).toMatchObject({ level: 2, xp: 0, skills: { savagery: 1 } });
    const thrice = gainLeaderXp(data, 'north', once, leaderXpToNext(data, 2) + leaderXpToNext(data, 3) + 3);
    expect(thrice).toMatchObject({ level: 4, xp: 3, skills: { savagery: 1, dread: 1, thick_hide: 1 } });
    expect(leaderEffects(data, thrice)).toEqual({ attack: 0.04, defense: 0.04, nerve: 0.06, loot: 0 });
    const top = gainLeaderXp(data, 'north', start, 1e9);
    expect(top.level).toBe(data.leaders.maxLevel);
    expect(top.xp).toBe(0);
    const ranks = Object.values(top.skills).reduce((a, b) => a + b, 0);
    expect(ranks).toBe(data.leaders.maxLevel - 1);
  });

  it('make their horde stronger, and stronger still against a grudge', () => {
    const base = enemyStats(data, 'north');
    const effects = { attack: 0.2, defense: 0.1, nerve: 0, loot: 0 };
    const led = ledStats(data, base, effects)('grey_wolf');
    const angry = ledStats(data, base, effects, true)('grey_wolf');
    expect(led.attack).toBeCloseTo(base('grey_wolf').attack * 1.2);
    expect(led.defense).toBeCloseTo(base('grey_wolf').defense * 1.1);
    expect(angry.attack).toBeCloseTo(base('grey_wolf').attack * (1.2 + data.leaders.grudge.attack));
    expect(ledStats(data, base, null)).toBe(base);
  });

  it('win, flee wounded with a grudge, or die with their horde', () => {
    const leader = newLeader(data, 'south', 3, []);
    const won = leaderAfterBattle(data, 'south', leader, { hordeWon: true, razed: true, kills: 8, wiped: false, villageId: 4 }, 10);
    expect(won).toMatchObject({ dead: false, woundMs: 0, grudgeVillageId: undefined });
    expect(won.state.level).toBeGreaterThan(1);
    const fled = leaderAfterBattle(data, 'south', leader, { hordeWon: false, kills: 2, wiped: false, villageId: 4 }, 10);
    expect(fled).toMatchObject({ dead: false, grudgeVillageId: 4, woundMs: (data.leaders.woundHours * 3_600_000) / 10 });
    expect(fled.state.xp).toBe(data.leaders.xp.battle + data.leaders.xp.escape + Math.floor(2 * data.leaders.xp.perKill));
    expect(leaderAfterBattle(data, 'south', leader, { hordeWon: false, kills: 0, wiped: true, villageId: 4 }, 10).dead).toBe(true);
  });

  it('rise stronger after one falls', () => {
    expect(riseLevel(data, 1)).toBe(1);
    expect(riseLevel(data, 9)).toBe(4);
    const rival = newLeader(data, 'west', 2, ['Otto'], 4);
    expect(rival.level).toBe(4);
    expect(Object.values(rival.skills).reduce((a, b) => a + b, 0)).toBe(3);
  });
});
