import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { hex } from '../src/sim/hex.js';
import { caravanFind, nextOffersAt, questMs, questOffers, questSlot, questWounds, questXp, type QuestWorld } from '../src/sim/quests.js';

const data = loadGameData();
const T0 = new Date('2026-06-01T00:00:00Z');
const world: QuestWorld = { seed: 7, speed: 1, startedAt: T0, fronts: ['north', 'south'], sites: [{ id: 3, q: 4, r: 0 }], gearLeft: true };
const hero = { accountId: 5, kind: 'dobrynya' };

describe('hero quests', () => {
  it('offers a few quests at a time, the same until new ones come', () => {
    const offers = questOffers(data, world, hero, hex(2, 0), T0);
    expect(offers).toHaveLength(data.quests.offers);
    expect(new Set(offers.map((o) => o.kind)).size).toBe(offers.length);
    expect(questOffers(data, world, hero, hex(2, 0), new Date(T0.getTime() + 60_000))).toEqual(offers);
    const later = nextOffersAt(data, world, T0);
    expect(questSlot(data, world, later)).toBe(1);
    expect(questOffers(data, world, hero, hex(2, 0), later).every((o) => o.id.startsWith('1:'))).toBe(true);
  });

  it('offers only what the world holds, and not what the hero already went on', () => {
    const bare: QuestWorld = { ...world, fronts: [], sites: [], gearLeft: false };
    expect(questOffers(data, bare, hero, hex(2, 0), T0).map((o) => o.kind)).toEqual(['caravan']);
    const done = ['0:caravan', '0:hoard', '0:ruins'];
    const kinds = questOffers(data, world, hero, hex(2, 0), T0, done).map((o) => o.kind).sort();
    expect(kinds).toEqual(['ambush', 'scout']);
  });

  it('takes the road there and back plus the work, faster for a quick hero', () => {
    const done = ['0:caravan', '0:hoard', '0:ambush', '0:scout'];
    const ruins = questOffers(data, world, hero, hex(2, 0), T0, done)[0]!;
    expect(ruins).toMatchObject({ kind: 'ruins', siteId: 3, distance: 2 });
    expect(ruins.hours).toBeCloseTo(data.quests.kinds.ruins.hours + 4 / data.heroes.speed);
    const quick = questOffers(data, world, { accountId: 5, kind: 'vasilisa' }, hex(2, 0), T0, done)[0]!;
    expect(quick.hours).toBeLessThan(ruins.hours);
    expect(questMs(ruins, 10)).toBe(Math.round((ruins.hours * 3_600_000) / 10));
  });

  it('pays more with level, more XP for a quick learner, and wounds by the seed', () => {
    expect(caravanFind(data, 1)).toEqual(data.quests.kinds.caravan.resources);
    expect(caravanFind(data, 11).wood).toBe(Math.round(data.quests.kinds.caravan.resources!.wood * 2));
    expect(questXp(data, { xp: 100 }, 'volkh')).toBe(120);
    expect(questXp(data, { xp: 100 }, 'ilya')).toBe(85);
    const offer = { id: '0:ambush', risk: 0.5 };
    expect(questWounds(offer, 1, 2, T0)).toBe(questWounds(offer, 1, 2, T0));
    expect(questWounds({ ...offer, risk: 0 }, 1, 2, T0)).toBe(false);
    expect(questWounds({ ...offer, risk: 1 }, 1, 2, T0)).toBe(true);
  });
});
