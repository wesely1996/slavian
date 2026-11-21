// Battle lines and maneuvers (battle.json lines, sim/lines.ts).
import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { battleRng, playerStats, resolveRound } from '../src/sim/battle.js';
import { battleLines, commandOf, NO_COMMAND, type Command, type Counts, type LinesInput } from '../src/sim/lines.js';

const data = loadGameData();
const rules = data.battle.lines;
const c = (infantry: number, cavalry = 0, archers = 0): Counts => ({ infantry, cavalry, archers });
const input = (over: Partial<LinesInput> = {}): LinesInput => ({ opening: false, attacker: NO_COMMAND, defender: NO_COMMAND, ground: { flat: 1 }, ...over });
const led = (over: Partial<Command>): Command => ({ ...NO_COMMAND, ...over });

describe('battle lines', () => {
  it('lets the smaller army set the width', () => {
    const lines = battleLines(data, input({ attacker: led({ cap: 'none' }) }), c(100), c(25));
    expect(lines.attacker.dealt.infantry).toBeCloseTo(0.25);
    expect(lines.defender.dealt.infantry).toBe(1);
    expect(lines.maneuver).toBeNull();
  });

  it('opens with a volley of arrows at the infantry', () => {
    const fight = (opening: boolean) =>
      resolveRound(
        data,
        { units: { archer: 50, axe_levy: 50 }, stance: 'balanced', stats: playerStats(data), home: false },
        { units: { axe_levy: 100, horseman: 50 }, stance: 'balanced', stats: playerStats(data), home: false },
        battleRng(1, 1, 1),
        undefined,
        { flat: 1 },
        input({ opening }),
      );
    const volley = fight(true);
    expect(volley.defenderLosses.horseman ?? 0).toBe(0);
    expect(volley.defenderLosses.axe_levy).toBeGreaterThan(0);
    // The defenders have no archers: nothing comes back.
    expect(volley.attackerLosses).toEqual({});
    expect(fight(false).attackerLosses.archer ?? 0).toBeGreaterThan(0);
  });

  it('flanks with cavalry on flat land and with infantry on hills', () => {
    const flat = battleLines(data, input(), c(20, 30), c(20, 20));
    expect(flat.maneuver).toEqual({ by: 'attacker', kind: 'flank' });
    // 20 of the 50 fight in the line; the 30 beyond strike in full and take half.
    expect(flat.attacker.dealt.cavalry).toBeCloseTo((40 + 1 * 10) / 50);
    expect(flat.attacker.taken).toBeCloseTo((40 + 0.5 * 10) / 50);
    expect(battleLines(data, input({ ground: { hills: 1 } }), c(20, 30), c(20, 20)).maneuver).toBeNull();
    expect(battleLines(data, input({ ground: { hills: 1 } }), c(30, 20), c(20, 20)).maneuver?.kind).toBe('flank');
  });

  it('needs a commander for a pincer, and open ground around', () => {
    const big = c(10, 40);
    const small = c(10, 15);
    expect(battleLines(data, input(), big, small).maneuver?.kind).toBe('flank');
    const general = led({ general: rules.commander.general });
    const pincer = battleLines(data, input({ attacker: general }), big, small);
    expect(pincer.maneuver?.kind).toBe('pincer');
    expect(pincer.attacker.dealt.cavalry).toBeCloseTo((25 + 2 * 25) / 50);
    expect(battleLines(data, input({ attacker: led({ skills: { horse_lord: 3 } }) }), big, small).maneuver?.kind).toBe('pincer');
    // Rivers, lakes and mountains leave no room to close the pincer.
    expect(battleLines(data, input({ attacker: general, ground: { flat: 1, water: 1 } }), big, small).maneuver?.kind).toBe('flank');
    // A road the general knows makes do with a lower rank.
    expect(battleLines(data, input({ attacker: led({ general: rules.commander.general - 1, road: true }) }), big, small).maneuver?.kind).toBe('pincer');
  });

  it('encircles at three to one, but never a fort by the water', () => {
    const around = battleLines(data, input(), c(60), c(20));
    expect(around.maneuver?.kind).toBe('encircle');
    expect(around.attacker.dealt.infantry).toBe(rules.encircle.dealt);
    expect(around.attacker.taken).toBe(rules.encircle.taken);
    expect(battleLines(data, input({ fort: 'defender', ground: { flat: 1, water: 1 } }), c(60), c(20)).maneuver).toBeNull();
    // A cap holds a side back.
    expect(battleLines(data, input({ attacker: led({ cap: 'flank' }) }), c(60, 30), c(20, 10)).maneuver?.kind).toBe('flank');
  });

  it('turns into a breakthrough when the surplus is destroyed', () => {
    const begun = battleLines(data, input(), c(20, 30), c(20, 20));
    expect(begun.state.active?.kind).toBe('flank');
    // The defenders cut down the riders beyond the line.
    const broken = battleLines(data, input({ state: begun.state }), c(20, 25), c(18, 18));
    expect(broken.breakthrough).toEqual({ by: 'defender', kind: 'flank' });
    expect(broken.defender.dealt.infantry).toBeCloseTo(1 + rules.breakthrough.dealtBonus);
    expect(broken.defender.taken).toBeCloseTo(rules.flank.surplusTaken);
    // The attackers maneuver no more.
    const after = battleLines(data, input({ state: broken.state }), c(20, 25), c(10, 5));
    expect(after.maneuver).toBeNull();
    // Help that joins the defenders later shares in it only in part.
    const helped = battleLines(data, input({ state: broken.state }), c(20, 25), c(36, 36));
    expect(helped.defender.dealt.infantry).toBeLessThan(1 + rules.breakthrough.dealtBonus);
  });

  it("ends a maneuver without a breakthrough when the smaller side is reinforced", () => {
    const begun = battleLines(data, input(), c(20, 30), c(20, 20));
    const helped = battleLines(data, input({ state: begun.state }), c(20, 30), c(30, 30));
    expect(helped.breakthrough).toBeNull();
    expect(helped.state.active).toBeUndefined();
  });

  it('lets a Shield Bearer close ranks and keep his flank', () => {
    const shield = led({ skills: { shield_bearer: rules.shieldBearer.rank } });
    const against = battleLines(data, input({ defender: shield }), c(20, 30), c(20, 20));
    expect(against.defender.taken).toBeCloseTo(rules.shieldBearer.taken);
    const begun = battleLines(data, input({ attacker: shield }), c(20, 30), c(20, 20));
    const broken = battleLines(data, input({ attacker: shield, state: begun.state }), c(20, 25), c(18, 18));
    expect(broken.breakthrough?.by).toBe('defender');
    expect(broken.maneuver).toEqual({ by: 'attacker', kind: 'flank' });
  });

  it('fights at a bridge on a narrow front', () => {
    const lines = battleLines(data, input({ bridge: true }), c(100, 20, 40), c(20, 0, 30));
    // Half of the smaller side's infantry: 10.
    expect(lines.attacker.dealt.infantry).toBeCloseTo(10 / 120);
    expect(lines.attacker.dealt.archers).toBeCloseTo(10 / 40);
    expect(lines.defender.dealt.archers).toBeCloseTo(10 / 30);
    expect(lines.maneuver).toBeNull();
  });

  it('eases a fort holder and hampers its attacker', () => {
    // 1.25 x 1.5 = 1.875: 35 riders against 20 no longer flank a fort.
    expect(battleLines(data, input({ fort: 'defender' }), c(10, 35), c(20, 20)).maneuver).toBeNull();
    expect(battleLines(data, input({ fort: 'attacker' }), c(16, 26), c(20, 20)).maneuver?.kind).toBe('flank');
    expect(battleLines(data, input(), c(16, 26), c(20, 20)).maneuver).toBeNull();
  });

  it("takes a side's best ranks among its leaders", () => {
    const command = commandOf('pincer', [{ hero: { skills: { battle_fury: 2 } } }, { hero: { skills: { battle_fury: 4 } }, general: { level: 3 } }]);
    expect(command).toEqual({ cap: 'pincer', general: 3, skills: { battle_fury: 4 }, leader: 0, road: false });
  });
});
