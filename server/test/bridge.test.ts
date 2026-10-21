import { describe, expect, it } from 'vitest';
import { loadGameData } from '../src/data/index.js';
import { completeQuest, donate, embersWanted, isReady, needs, newBridge, raised, stagesStanding, startRaising } from '../src/sim/bridge.js';
import { waveFactor } from '../src/sim/difficulty.js';

const data = loadGameData();
const T0 = new Date('2026-06-01T00:00:00Z');
const none = { wood: 0, stone: 0, grain: 0, iron: 0 };

describe('the Kalinov Bridge', () => {
  it('has a story for every stage and every quest', () => {
    expect(data.bridge.story.length).toBeGreaterThan(40);
    for (const stage of data.bridge.stages) {
      expect(stage.story.length).toBeGreaterThan(40);
      for (const quest of stage.quests) expect(quest.story.length).toBeGreaterThan(30);
    }
    expect(data.bridge.stages).toHaveLength(5);
  });

  it('takes only what the open stage still needs', () => {
    const bridge = newBridge(T0, 100);
    const cost = data.bridge.stages[0]!.cost;
    const first = donate(data, bridge, { resources: { ...none, stone: 1000 }, embers: 0 });
    expect(first.taken.stone).toBe(1000);
    const second = donate(data, first.bridge, { resources: { wood: 99_999, stone: 99_999, grain: 0, iron: 0 }, embers: 5 });
    expect(second.taken).toEqual({ wood: cost.wood, stone: cost.stone - 1000, grain: 0, iron: 0 });
    expect(second.embers).toBe(0);
    expect(needs(data, second.bridge).resources).toEqual({ wood: 0, stone: 0, grain: cost.grain, iron: cost.iron });
    expect(() => donate(data, second.bridge, { resources: { ...none, wood: 10 }, embers: 0 })).toThrow(/needs none/);
  });

  it('opens with its quests, rises, and moves on to the next stage', () => {
    let bridge = donate(data, newBridge(T0, 100), { resources: data.bridge.stages[0]!.cost, embers: 0 }).bridge;
    expect(isReady(data, bridge)).toBe(false);
    expect(completeQuest(data, bridge, 'lair', T0)).toBeNull();
    bridge = completeQuest(data, bridge, 'site', T0)!;
    expect(completeQuest(data, bridge, 'site', T0)).toBeNull();
    expect(isReady(data, bridge)).toBe(true);
    bridge = startRaising(data, bridge, T0, 10);
    expect(bridge.raisedAt).toBe(new Date(T0.getTime() + (data.bridge.buildHours * 3_600_000) / 10).toISOString());
    expect(() => donate(data, bridge, { resources: { ...none, wood: 1 }, embers: 0 })).toThrow(/being raised/);
    bridge = raised(data, bridge, T0, 90);
    expect(bridge).toMatchObject({ stage: 1, status: 'open', sanctityAtStart: 90, quests: {}, embers: 0 });
    expect(stagesStanding(bridge)).toBe(1);
    let last = { ...bridge, stage: data.bridge.stages.length - 1 };
    last = raised(data, startRaising(data, last, T0, 1), T0, 90);
    expect(last.status).toBe('complete');
    expect(needs(data, last).quests).toEqual([]);
  });

  it("counts the Embers a stage still wants, the torc's among them", () => {
    const at = (stage: number) => ({ ...newBridge(T0, 100), stage });
    expect(embersWanted(data, at(0))).toBe(0);
    expect(embersWanted(data, at(1))).toBe(data.bridge.stages[1]!.embers);
    expect(embersWanted(data, { ...at(1), embers: data.bridge.stages[1]!.embers })).toBe(0);
    const arch = data.bridge.stages.length - 1;
    expect(embersWanted(data, at(arch))).toBe(data.bridge.stages[arch]!.embers + data.bridge.ritualEmbers);
    expect(embersWanted(data, { ...at(arch), quests: { ritual: T0.toISOString() } })).toBe(data.bridge.stages[arch]!.embers);
  });

  it('makes waves bigger with every stage standing', () => {
    const base = { players: 1, villages: 1, armyAttack: 0, waveIndex: 2 };
    expect(waveFactor(data, 'normal', { ...base, bridgeStages: 3 })).toBeCloseTo(1 + 3 * data.bridge.powerPerStage);
  });
});
