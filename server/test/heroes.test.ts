import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { equip, freeHeroKind, gainXp, heroBonuses, heroFactor, learnSkill, newHero, rollDrop, rosterBonuses, unequip, woundMs, xpToNext, type HeroState } from '../src/sim/heroes.js';

const data = loadGameData();

describe('heroes', () => {
  const hero = newHero(data, 'dobrynya');

  it('are born from the roster with its name, at level 1', () => {
    expect(hero).toMatchObject({ kind: 'dobrynya', name: 'Dobrynya', level: 1, xp: 0, skillPoints: 0, skills: {}, gear: {}, inventory: [] });
  });

  it('each have their strengths, weaknesses and traits', () => {
    expect(Object.keys(data.heroes.roster).length).toBeGreaterThanOrEqual(5);
    for (const kind of Object.keys(data.heroes.roster)) {
      const def = data.heroes.roster[kind]!;
      expect(Object.keys(def.effects).length).toBeGreaterThanOrEqual(2);
      expect(def.traits.length).toBeGreaterThanOrEqual(1);
    }
    expect(rosterBonuses(data, 'volkh')).toMatchObject({ researchTime: -0.12, 'attack.all': -0.06, woundTime: -0.5 });
    expect(rosterBonuses(data, null)).toEqual({});
    expect(heroFactor(data, 'vasilisa', 'heroSpeed')).toBeCloseTo(1.25);
    expect(woundMs(data, 1, 'volkh')).toBe(woundMs(data, 1) / 2);
  });

  it('are handed out so no two in a group are the same', () => {
    const taken: (string | null)[] = [];
    for (let i = 0; i < Object.keys(data.heroes.roster).length; i++) taken.push(freeHeroKind(data, taken));
    expect(new Set(taken).size).toBe(taken.length);
    expect(freeHeroKind(data, taken)).toBeNull();
  });

  it('level up with XP, one skill point a level', () => {
    expect(xpToNext(data, 1)).toBe(data.heroes.levelXp.base);
    const once = gainXp(data, hero, xpToNext(data, 1) + 5);
    expect(once).toMatchObject({ level: 2, xp: 5, skillPoints: 1 });
    const many = gainXp(data, hero, xpToNext(data, 1) + xpToNext(data, 2) + xpToNext(data, 3));
    expect(many).toMatchObject({ level: 4, xp: 0, skillPoints: 3 });
    expect(gainXp(data, hero, 1e9)).toMatchObject({ level: data.heroes.maxLevel, xp: 0 });
  });

  it('learn skills with points, up to their highest rank', () => {
    expect(() => learnSkill(data, hero, 'battle_fury')).toThrow(/No skill points/);
    let h: HeroState = { ...hero, skillPoints: 9 };
    h = learnSkill(data, learnSkill(data, h, 'battle_fury'), 'battle_fury');
    expect(h.skills).toEqual({ battle_fury: 2 });
    expect(h.skillPoints).toBe(7);
    expect(heroBonuses(data, h)['attack.all']).toBeCloseTo(0.08);
    h = learnSkill(data, learnSkill(data, learnSkill(data, h, 'spearhead'), 'spearhead'), 'spearhead');
    expect(() => learnSkill(data, h, 'spearhead')).toThrow(/highest rank/);
    expect(() => learnSkill(data, h, 'flying')).toThrow(/Unknown skill/);
  });

  it('wear gear, one item per slot, and gain set bonuses', () => {
    let h: HeroState = { ...hero, inventory: ['perun_axe', 'ash_spear', 'thunder_banner'] };
    expect(() => equip(data, h, 'bear_cloak')).toThrow(/no such item/);
    h = equip(data, h, 'ash_spear');
    h = equip(data, h, 'perun_axe');
    expect(h.gear).toEqual({ weapon: 'perun_axe' });
    expect([...h.inventory].sort()).toEqual(['ash_spear', 'thunder_banner']);
    expect(heroBonuses(data, h)['attack.all']).toBeCloseTo(0.08);
    h = equip(data, h, 'thunder_banner');
    // Axe 8% + banner 4% + the full Thunder set 5%.
    expect(heroBonuses(data, h)['attack.all']).toBeCloseTo(0.17);
    h = unequip(h, 'weapon');
    expect(h.gear).toEqual({ banner: 'thunder_banner' });
    expect(() => unequip(h, 'weapon')).toThrow(/Nothing in that slot/);
  });

  it('may find gear after a win, never twice the same', () => {
    const drops = Array.from({ length: 50 }, (_, battle) => rollDrop(data, hero, 99, battle));
    const found = drops.filter((d): d is string => d !== null);
    expect(found.length).toBeGreaterThan(5);
    expect(found.length).toBeLessThan(45);
    for (const item of found) expect(data.heroes.items[item]).toBeDefined();
    const owner = { ...hero, inventory: Object.keys(data.heroes.items) };
    expect(drops.map((_, battle) => rollDrop(data, owner, 99, battle)).every((d) => d === null)).toBe(true);
  });
});
