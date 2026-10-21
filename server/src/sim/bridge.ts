// The Kalinov Bridge (PLAN.md §10): five stages, each paid from the vault
// with resources and Svarog's Ember and opened by quests, then raised over
// some hours. Numbers in data/bridge.json.
import type { BridgeQuest, GameData } from '../data/index.js';
import { RuleError } from '../errors.js';
import { mapResources, RESOURCE_KINDS, type Resources } from './resources.js';

export interface BridgeState {
  // The stage being built (0-based); stages.length once the bridge stands.
  readonly stage: number;
  // Paid towards the current stage.
  readonly donated: Resources;
  readonly embers: number;
  // Quests of the current stage done, with when.
  readonly quests: Partial<Record<BridgeQuest, string>>;
  readonly stageStartedAt: string;
  // Sanctity when the stage began (for the unscathed quest).
  readonly sanctityAtStart: number;
  // open: taking donations and quests; raising: being built until raisedAt;
  // complete: all stages stand.
  readonly status: 'open' | 'raising' | 'complete';
  readonly raisedAt: string | null;
}

export function newBridge(at: Date, sanctity: number): BridgeState {
  return {
    stage: 0,
    donated: mapResources(() => 0),
    embers: 0,
    quests: {},
    stageStartedAt: at.toISOString(),
    sanctityAtStart: sanctity,
    status: 'open',
    raisedAt: null,
  };
}

export function currentStage(data: GameData, bridge: BridgeState) {
  return bridge.status === 'complete' ? null : (data.bridge.stages[bridge.stage] ?? null);
}

// What the stage still needs.
export function needs(data: GameData, bridge: BridgeState): { resources: Resources; embers: number; quests: BridgeQuest[] } {
  const stage = currentStage(data, bridge);
  if (!stage) return { resources: mapResources(() => 0), embers: 0, quests: [] };
  return {
    resources: mapResources((kind) => Math.max(0, stage.cost[kind] - bridge.donated[kind])),
    embers: Math.max(0, stage.embers - bridge.embers),
    quests: stage.quests.map((q) => q.kind).filter((q) => !bridge.quests[q]),
  };
}

// Svarog's Embers the open stage still wants: its own and, when its quest is
// open, the ritual torc's.
export function embersWanted(data: GameData, bridge: BridgeState): number {
  const need = needs(data, bridge);
  return need.embers + (need.quests.includes('ritual') ? data.bridge.ritualEmbers : 0);
}

export function isReady(data: GameData, bridge: BridgeState): boolean {
  const need = needs(data, bridge);
  return bridge.status === 'open' && RESOURCE_KINDS.every((k) => need.resources[k] === 0) && need.embers === 0 && need.quests.length === 0;
}

// Takes what the stage still needs from what is offered.
export function donate(
  data: GameData,
  bridge: BridgeState,
  offer: { resources: Resources; embers: number },
): { bridge: BridgeState; taken: Resources; embers: number } {
  if (bridge.status !== 'open') throw new RuleError(bridge.status === 'raising' ? 'This stage is being raised' : 'The bridge stands');
  const need = needs(data, bridge);
  const taken = mapResources((kind) => Math.max(0, Math.min(offer.resources[kind], need.resources[kind])));
  const embers = Math.max(0, Math.min(offer.embers, need.embers));
  if (RESOURCE_KINDS.every((k) => taken[k] === 0) && embers === 0) throw new RuleError('The stage needs none of that');
  return {
    bridge: { ...bridge, donated: mapResources((kind) => bridge.donated[kind] + taken[kind]), embers: bridge.embers + embers },
    taken,
    embers,
  };
}

// A quest of the open stage is done (null: not one of its open quests).
export function completeQuest(data: GameData, bridge: BridgeState, quest: BridgeQuest, at: Date): BridgeState | null {
  if (bridge.status !== 'open' || bridge.quests[quest]) return null;
  if (!currentStage(data, bridge)?.quests.some((q) => q.kind === quest)) return null;
  return { ...bridge, quests: { ...bridge.quests, [quest]: at.toISOString() } };
}

export function startRaising(data: GameData, bridge: BridgeState, at: Date, worldSpeed: number): BridgeState {
  const raisedAt = new Date(at.getTime() + (data.bridge.buildHours * 3_600_000) / worldSpeed);
  return { ...bridge, status: 'raising', raisedAt: raisedAt.toISOString() };
}

// The stage stands: on to the next (or the bridge is complete).
export function raised(data: GameData, bridge: BridgeState, at: Date, sanctity: number): BridgeState {
  const stage = bridge.stage + 1;
  if (stage >= data.bridge.stages.length) return { ...bridge, stage, status: 'complete', raisedAt: null, quests: {} };
  return { ...newBridge(at, sanctity), stage };
}

// Stages standing (for group power).
export function stagesStanding(bridge: BridgeState | null): number {
  return bridge?.stage ?? 0;
}
