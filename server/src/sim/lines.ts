// Battle lines and maneuvers (battle.json lines). Armies meet in a line
// the smaller one sets the width of: the larger fights with as many troops
// as the smaller has, the rest wait behind. Round 1 is an exchange of
// missiles. From then on the larger side may maneuver (flank, pincer,
// encircle) and bring its surplus in; if the smaller side destroys that
// surplus, it breaks through and the tables turn.
import type { GameData, Maneuver } from '../data/index.js';
import { generalTrait } from './generals.js';
import type { Ground } from './ground.js';

export type SideId = 'attacker' | 'defender';
export type Move = Exclude<Maneuver, 'none'>;
export const LINE_FAMILIES = ['infantry', 'cavalry', 'archers'] as const;
export type LineFamily = (typeof LINE_FAMILIES)[number];
export type Counts = Readonly<Record<LineFamily, number>>;

const ORDER: readonly Maneuver[] = ['none', 'flank', 'pincer', 'encircle'];

// Who commands a side, as far as maneuvers go.
export interface Command {
  // How far it maneuvers at most (an army's or a garrison's choice).
  readonly cap: Maneuver;
  // The best general's level among it (0: none).
  readonly general: number;
  // The leading hero's skill ranks.
  readonly skills: Readonly<Record<string, number>>;
  // A horde's leader's level (0: none).
  readonly leader: number;
  // A player's side fighting on its own road (battle.json lines.road).
  readonly road: boolean;
  // Its commanders' traits: how much stronger (or weaker) each maneuver,
  // and a breakthrough, comes off (maneuver.<kind> effects).
  readonly power?: Readonly<Partial<Record<Move | 'breakthrough', number>>>;
}

export const NO_COMMAND: Command = { cap: 'encircle', general: 0, skills: {}, leader: 0, road: false };

const power = (command: Command, kind: Move | 'breakthrough') => command.power?.[kind] ?? 0;

// What a battle carries from round to round.
export interface LineState {
  // The maneuver under way, and the smaller side as it was when it began.
  readonly active?: { readonly by: SideId; readonly kind: Move; readonly weak: Counts } | undefined;
  // Sides that lost their maneuver to a breakthrough: they maneuver no more.
  readonly spent?: readonly SideId[] | undefined;
  // The side that broke through, how, and its numbers then.
  readonly breakthrough?: { readonly by: SideId; readonly kind: Move; readonly base: number } | undefined;
  // A Shield Bearer's flank, kept through a breakthrough.
  readonly kept?: { readonly by: SideId } | undefined;
}

export interface LinesInput {
  // Round 1: only archers shoot, at the infantry.
  readonly opening: boolean;
  readonly attacker: Command;
  readonly defender: Command;
  readonly ground?: Ground | undefined;
  // At a bridge: a narrow front and no maneuvers.
  readonly bridge?: boolean | undefined;
  // The side holding a fort on the battle's hex.
  readonly fort?: SideId | null | undefined;
  // Nobody maneuvers (behind standing walls).
  readonly still?: boolean | undefined;
  readonly state?: LineState | undefined;
}

export interface SideLine {
  // The share of each family's blows that strikes.
  readonly dealt: Readonly<Record<LineFamily, number>>;
  // The share of the blows aimed at it that lands.
  readonly taken: number;
}

export interface Lines {
  readonly opening: boolean;
  readonly attacker: SideLine;
  readonly defender: SideLine;
  readonly state: LineState;
  // What happened this round, for the report.
  readonly maneuver: { readonly by: SideId; readonly kind: Move } | null;
  readonly breakthrough: { readonly by: SideId; readonly kind: Move } | null;
}

const sum = (c: Counts) => c.infantry + c.cavalry + c.archers;
const other = (side: SideId): SideId => (side === 'attacker' ? 'defender' : 'attacker');
const flat = (dealt: number): Record<LineFamily, number> => ({ infantry: dealt, cavalry: dealt, archers: dealt });

// Whether `big` may make `kind` against `small` on this ground.
function can(data: GameData, input: LinesInput, by: SideId, kind: Move, big: Counts, small: Counts): boolean {
  const rules = data.battle.lines;
  const command = input[by];
  const hills = (input.ground?.hills ?? 0) > 0;
  let factor = 1;
  if (command.road) factor -= rules.road.ratioCut;
  if (input.fort === by) factor *= rules.fort.holderFactor;
  else if (input.fort) factor *= rules.fort.attackerFactor;
  // On hills the infantry carries it, on flat land the cavalry.
  const main = hills ? 'infantry' : 'cavalry';
  const second = hills ? 'cavalry' : 'infantry';
  if (kind === 'flank') return big[main] > 0 && big[main] >= rules.flank.ratio * factor * small[main];
  if (kind === 'pincer') {
    if ((input.ground?.water ?? 0) > 0 || (input.ground?.mountain ?? 0) > 0) return false;
    const cut = command.road ? rules.road.rankCut : 0;
    const c = rules.commander;
    const skill = (id: string) => command.skills[id] ?? 0;
    const led =
      (command.general > 0 && command.general >= c.general - cut) ||
      (skill('battle_fury') > 0 && skill('battle_fury') >= c.battleFury - cut) ||
      (!hills && skill('horse_lord') > 0 && skill('horse_lord') >= c.horseLord - cut) ||
      (hills && skill('spearhead') > 0 && skill('spearhead') >= c.spearhead - cut) ||
      (command.leader > 0 && command.leader >= c.leader);
    if (!led) return false;
    const pure = big[main] > 0 && big[main] >= rules.pincer.ratio * factor * small[main];
    const mixed = big[main] + big[second] > 0 && big[main] + big[second] >= rules.pincer.mixedRatio * factor * (small[main] + small[second]);
    return pure || mixed;
  }
  // A fort by the water can't be surrounded.
  if (input.fort === other(by) && (input.ground?.water ?? 0) > 0) return false;
  return sum(big) >= rules.encircle.ratio * factor * sum(small);
}

// The best maneuver `by` may make, up to its cap.
function best(data: GameData, input: LinesInput, by: SideId, big: Counts, small: Counts): Move | null {
  const cap = ORDER.indexOf(input[by].cap);
  for (const kind of ['encircle', 'pincer', 'flank'] as const) {
    if (ORDER.indexOf(kind) <= cap && can(data, input, by, kind, big, small)) return kind;
  }
  return null;
}

function shieldBearer(data: GameData, command: Command): boolean {
  return (command.skills.shield_bearer ?? 0) >= data.battle.lines.shieldBearer.rank;
}

// The lines for this round, from both sides' fighting troops by family.
export function battleLines(data: GameData, input: LinesInput, attacker: Counts, defender: Counts): Lines {
  const rules = data.battle.lines;
  const counts: Record<SideId, Counts> = { attacker, defender };
  const state: LineState = input.state ?? {};
  const line: Record<SideId, { dealt: Record<LineFamily, number>; taken: number }> = {
    attacker: { dealt: flat(1), taken: 1 },
    defender: { dealt: flat(1), taken: 1 },
  };
  const ta = sum(attacker);
  const td = sum(defender);
  const done = (next: LineState, maneuver: Lines['maneuver'] = null, breakthrough: Lines['breakthrough'] = null): Lines => ({
    opening: input.opening,
    attacker: line.attacker,
    defender: line.defender,
    state: next,
    maneuver,
    breakthrough,
  });
  if (ta === 0 || td === 0) return done(state);
  const big: SideId = ta > td ? 'attacker' : 'defender';
  const small = other(big);
  // At a bridge: half the smaller side's infantry wide, archers too.
  if (input.bridge) {
    const width = Math.max(1, Math.floor(counts[small].infantry / 2));
    for (const side of ['attacker', 'defender'] as const) {
      const c = counts[side];
      const melee = Math.min(1, width / Math.max(1, c.infantry + c.cavalry));
      line[side].dealt = { infantry: melee, cavalry: melee, archers: Math.min(1, width / Math.max(1, c.archers)) };
    }
    return done(state);
  }
  // The smaller side sets the width.
  const tb = sum(counts[big]);
  const ts = sum(counts[small]);
  if (tb > ts) line[big].dealt = flat(ts / tb);
  if (input.opening) return done(state);

  let next: LineState = state;
  let breakthrough: Lines['breakthrough'] = null;
  let maneuver: Lines['maneuver'] = null;
  // A maneuver under way: still on, given up, or broken through.
  if (state.active) {
    const { by, kind, weak } = state.active;
    const holds = can(data, input, by, kind, counts[by], weak);
    if (!holds) {
      breakthrough = { by: other(by), kind };
      const keep = kind === 'flank' && shieldBearer(data, input[by]);
      next = {
        ...next,
        active: undefined,
        spent: keep ? next.spent : [...(next.spent ?? []), by],
        breakthrough: { by: other(by), kind, base: sum(weak) },
        kept: keep ? { by } : next.kept,
      };
    } else if (by === big && can(data, input, by, kind, counts[by], counts[other(by)])) {
      maneuver = { by, kind };
    } else {
      // The smaller side grew (help came): the maneuver ends, nobody breaks through.
      next = { ...next, active: undefined };
    }
  }
  if (!maneuver && !next.active && !next.kept && !input.still && !(next.spent ?? []).includes(big) && next.breakthrough?.by !== small) {
    const kind = best(data, input, big, counts[big], counts[small]);
    if (kind) {
      maneuver = { by: big, kind };
      next = { ...next, active: { by: big, kind, weak: { ...counts[small] } } };
    }
  }
  // A Shield Bearer's flank goes on whatever happens.
  if (!maneuver && next.kept && next.kept.by === big) maneuver = { by: big, kind: 'flank' };

  if (maneuver) {
    const x = tb - ts;
    const boost = 1 + power(input[big], maneuver.kind);
    if (maneuver.kind === 'encircle') {
      line[big] = { dealt: flat(rules.encircle.dealt * boost), taken: rules.encircle.taken };
    } else {
      const r = rules[maneuver.kind];
      line[big] = { dealt: flat((ts + r.surplusDealt * boost * x) / tb), taken: (ts + r.surplusTaken * x) / tb };
    }
    // Outmaneuvered, a Shield Bearer's men close up.
    if (shieldBearer(data, input[small])) line[small] = { ...line[small], taken: line[small].taken * rules.shieldBearer.taken };
  }
  // The side that broke through strikes harder and takes less, its newcomers
  // sharing in it only as far as the troops who did it.
  const through = next.breakthrough;
  if (through) {
    const side = through.by;
    const share = Math.min(1, through.base / Math.max(1, sum(counts[side])));
    const dealt = (through.kind === 'encircle' ? rules.encircle.dealt : rules[through.kind].surplusDealt) + rules.breakthrough.dealtBonus * (1 + power(input[side], 'breakthrough'));
    const taken = through.kind === 'encircle' ? rules.encircle.taken : rules[through.kind].surplusTaken;
    const d = 1 + (dealt - 1) * share;
    line[side] = {
      dealt: { infantry: line[side].dealt.infantry * d, cavalry: line[side].dealt.cavalry * d, archers: line[side].dealt.archers * d },
      taken: line[side].taken * (1 - (1 - taken) * share),
    };
    if (shieldBearer(data, input[side]) && !maneuver) line[side] = { ...line[side], taken: line[side].taken * rules.shieldBearer.taken };
  }
  return done(next, maneuver, breakthrough);
}

// Who fights a battle in lines, and where: what stays the same each round.
export interface LineSetup {
  readonly attacker: Command;
  readonly defender: Command;
  readonly fort?: SideId | null | undefined;
  readonly bridge?: boolean | undefined;
  readonly still?: boolean | undefined;
  // No opening volley (an ambush falls on the enemy at once).
  readonly noOpening?: boolean | undefined;
}

// The lines input for `round` of a battle set up so, with the state the
// last round left.
export function linesFor(setup: LineSetup, round: number, state: LineState | undefined): LinesInput {
  return {
    opening: round === 1 && !setup.noOpening,
    attacker: setup.attacker,
    defender: setup.defender,
    fort: setup.fort,
    bridge: setup.bridge,
    still: setup.still,
    state,
  };
}

// A side's command: its cap, its best general, its leading hero's skills
// (the best rank of each among its heroes), a horde's leader.
// Its commanders' traits add up (heroes.json roster traits, generals.traits).
export function commandOf(
  data: GameData,
  cap: Maneuver,
  leaders: readonly {
    readonly hero?: { readonly skills: Readonly<Record<string, number>>; readonly kind?: string | null } | null;
    readonly general?: { readonly level: number; readonly id: number } | null;
  }[],
  road = false,
  leader = 0,
): Command {
  const skills: Record<string, number> = {};
  let general = 0;
  const shares: Partial<Record<Move | 'breakthrough', number>> = {};
  const add = (effects: Readonly<Record<string, number>>) => {
    for (const [key, value] of Object.entries(effects)) {
      const kind = MANEUVER_KEY.exec(key)?.[1] as Move | 'breakthrough' | undefined;
      if (kind) shares[kind] = (shares[kind] ?? 0) + value;
    }
  };
  for (const l of leaders) {
    for (const [id, rank] of Object.entries(l.hero?.skills ?? {})) skills[id] = Math.max(skills[id] ?? 0, rank);
    for (const t of (l.hero?.kind ? data.heroes.roster[l.hero.kind]?.traits : undefined) ?? []) add(t.effects);
    if (l.general) {
      general = Math.max(general, l.general.level);
      add(generalTrait(data, l.general.id).effects);
    }
  }
  const limit = data.battle.lines.traitCap;
  const power = Object.fromEntries(Object.entries(shares).map(([k, v]) => [k, Math.max(-limit, Math.min(limit, v))]));
  return { cap, general, skills, leader, road, ...(Object.keys(power).length > 0 ? { power } : {}) };
}

const MANEUVER_KEY = /^maneuver\.(flank|pincer|encircle|breakthrough)$/;

// The round's report: the maneuver made, the breakthrough.
export function linesLog(lines: Lines | undefined): { maneuver?: { by: SideId; kind: Move }; breakthrough?: { by: SideId; kind: Move } } {
  return {
    ...(lines?.maneuver ? { maneuver: lines.maneuver } : {}),
    ...(lines?.breakthrough ? { breakthrough: lines.breakthrough } : {}),
  };
}

// A battle's setup with the state the round's lines left (none kept while
// nothing is under way); the same object when nothing changed.
export function withLines<T extends { lines?: LineState }>(setup: T, lines: Lines | undefined): T {
  if (!lines) return setup;
  const next = Object.fromEntries(Object.entries(lines.state).filter(([, v]) => v !== undefined)) as LineState;
  if (JSON.stringify(next) === JSON.stringify(setup.lines ?? {})) return setup;
  if (Object.keys(next).length > 0) return { ...setup, lines: next };
  const { lines: _gone, ...rest } = setup;
  return rest as T;
}
