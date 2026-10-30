// Hero quests (PLAN.md M5 step 22, data/quests.json): the hero rides out
// alone for real time, and comes home with experience and what it went for,
// or wounded. A hero offers a few quests at a time, new ones every few game
// hours, drawn from what the world holds: a horde to ambush or count, an
// unguarded ancient site to search, a caravan or a hoard to find.
import type { GameData, QuestKind } from '../data/index.js';
import { hexDistance, type Hex } from './hex.js';
import { heroFactor } from './heroes.js';
import { createRng } from './rng.js';
import type { Front } from './mapgen.js';

const MS_PER_HOUR = 3_600_000;

export interface QuestOffer {
  // `${slot}:${kind}`: unique while the offer stands.
  readonly id: string;
  readonly kind: QuestKind;
  // The front whose next horde it is about (ambush, scout).
  readonly front: Front | null;
  // The site it searches (ruins).
  readonly siteId: number | null;
  // Hexes each way.
  readonly distance: number;
  // Game hours, there and back included.
  readonly hours: number;
  readonly xp: number;
  readonly risk: number;
}

// What the world holds for quests right now.
export interface QuestWorld {
  readonly seed: number;
  readonly speed: number;
  readonly startedAt: Date;
  // Fronts with a horde not yet set out.
  readonly fronts: readonly Front[];
  // How much each front's next horde hates already (horde.json hatred).
  readonly hatred?: Partial<Record<Front, number>>;
  // Ancient sites nobody has searched and nothing guards.
  readonly sites: readonly { id: number; q: number; r: number }[];
  // Whether gear the hero doesn't have is left.
  readonly gearLeft: boolean;
}

// The offer period `at` falls in (new offers each period).
export function questSlot(data: GameData, world: Pick<QuestWorld, 'startedAt' | 'speed'>, at: Date): number {
  const gameHours = ((at.getTime() - world.startedAt.getTime()) * world.speed) / MS_PER_HOUR;
  return Math.max(0, Math.floor(gameHours / data.quests.refreshHours));
}

// When the current offers give way to new ones.
export function nextOffersAt(data: GameData, world: Pick<QuestWorld, 'startedAt' | 'speed'>, at: Date): Date {
  const slot = questSlot(data, world, at) + 1;
  return new Date(world.startedAt.getTime() + (slot * data.quests.refreshHours * MS_PER_HOUR) / world.speed);
}

// The quests a hero standing at `home` is offered at `at`, leaving out those
// it already went on (`done`, offer ids).
export function questOffers(
  data: GameData,
  world: QuestWorld,
  hero: { accountId: number; kind: string | null },
  home: Hex,
  at: Date,
  done: readonly string[] = [],
): QuestOffer[] {
  const slot = questSlot(data, world, at);
  const rng = createRng((world.seed ^ Math.imul(hero.accountId + 1, 0x85ebca6b) ^ Math.imul(slot + 1, 0xc2b2ae35)) >>> 0);
  const speed = data.heroes.speed * heroFactor(data, hero.kind, 'heroSpeed');
  const nearest = [...world.sites].sort((a, b) => hexDistance(home, a) - hexDistance(home, b) || a.id - b.id)[0];
  const open: QuestKind[] = (['ambush', 'scout', 'caravan', 'hoard', 'ruins'] as const).filter((kind) => {
    if (kind === 'ambush' || kind === 'scout') return world.fronts.length > 0;
    if (kind === 'hoard') return world.gearLeft;
    if (kind === 'ruins') return nearest !== undefined;
    return true;
  });
  // A shuffle by the seed, then the first few not yet done.
  for (let i = open.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [open[i], open[j]] = [open[j]!, open[i]!];
  }
  const offers: QuestOffer[] = [];
  for (const kind of open) {
    if (offers.length >= data.quests.offers) break;
    const id = `${slot}:${kind}`;
    if (done.includes(id)) continue;
    const def = data.quests.kinds[kind];
    const front = kind === 'ambush' || kind === 'scout' ? world.fronts[Math.floor(rng() * world.fronts.length)]! : null;
    const site = kind === 'ruins' ? nearest! : null;
    const distance = site ? hexDistance(home, site) : def.distance;
    // An ambush on a horde that hates already: riskier, and worth more.
    const hatred = kind === 'ambush' && front ? (world.hatred?.[front] ?? 0) : 0;
    offers.push({
      id,
      kind,
      front,
      siteId: site?.id ?? null,
      distance,
      hours: def.hours + (2 * distance) / speed,
      xp: Math.round(def.xp * (1 + hatred * (def.hatredXp ?? 0))),
      risk: Math.min(def.maxRisk ?? 1, def.risk + hatred * (def.hatredRisk ?? 0)),
    });
  }
  return offers;
}

// How long a quest keeps the hero away, in real time.
export function questMs(offer: Pick<QuestOffer, 'hours'>, worldSpeed: number): number {
  return Math.round((offer.hours * MS_PER_HOUR) / worldSpeed);
}

// What the hero brings home from a caravan quest, more as it rises in level.
export function caravanFind(data: GameData, level: number): Record<'wood' | 'stone' | 'grain' | 'iron', number> {
  const base = data.quests.kinds.caravan.resources ?? { wood: 0, stone: 0, grain: 0, iron: 0 };
  const scale = 1 + data.quests.perLevel * (level - 1);
  return {
    wood: Math.round(base.wood * scale),
    stone: Math.round(base.stone * scale),
    grain: Math.round(base.grain * scale),
    iron: Math.round(base.iron * scale),
  };
}

// Whether the hero comes home wounded, by the seed (fixed for one quest).
export function questWounds(offer: Pick<QuestOffer, 'risk' | 'id'>, seed: number, accountId: number, departsAt: Date): boolean {
  const rng = createRng((seed ^ Math.imul(accountId + 1, 0x27d4eb2f) ^ Math.floor(departsAt.getTime() / 1000)) >>> 0);
  return rng() < offer.risk;
}

// The XP a quest gives, times the hero's heroXp.
export function questXp(data: GameData, offer: Pick<QuestOffer, 'xp'>, kind: string | null): number {
  return Math.round(offer.xp * heroFactor(data, kind, 'heroXp'));
}
