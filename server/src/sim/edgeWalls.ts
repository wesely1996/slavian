// Walls along hex edges (data/field.json edgeWalls): what a tier costs and
// takes, and how long a horde takes to tear one down.
import type { GameData } from '../data/index.js';
import { mapResources, type Resources } from './resources.js';
import type { PathStep } from './waves.js';
import { edgeKey } from './land.js';
import { hex } from './hex.js';

export type WallKind = 'wall' | 'gate';

// What raising a wall (or a gatehouse) to `tier` costs.
export function wallTierCost(data: GameData, kind: WallKind, tier: number): Resources {
  const rules = data.field.edgeWalls;
  const base = rules.tiers[tier - 1]!.cost;
  if (kind === 'wall') return base;
  const gate = rules.gatehouse;
  return mapResources((r) => Math.round(base[r] * gate.costFactor) + (r === 'iron' ? gate.iron[tier - 1] ?? gate.iron.at(-1)! : 0));
}

// How long raising it to `tier` takes, in game seconds.
export function wallTierSeconds(data: GameData, kind: WallKind, tier: number): number {
  const seconds = data.field.edgeWalls.tiers[tier - 1]!.buildSeconds;
  return kind === 'gate' ? seconds * data.field.edgeWalls.gatehouse.timeFactor : seconds;
}

// How many game hours a horde takes to tear it down.
export function breakHours(data: GameData, wall: { gate: boolean; tier: number }): number {
  const hours = data.field.edgeWalls.tiers[Math.max(1, wall.tier) - 1]!.breakHours;
  return wall.gate ? hours * data.field.edgeWalls.gatehouse.breakFactor : hours;
}

// The fort wall ring level a gatehouse of `tier` counts as.
export function gateRingLevel(data: GameData, tier: number): number {
  const levels = data.field.edgeWalls.gatehouse.fortRingLevels;
  return levels[Math.min(levels.length, Math.max(1, tier)) - 1]!;
}

// A gatehouse on an edge of its owner's fort's hex is the fort's outermost
// wall ring (after its own 0..2): a village-style wall at gateRingLevel.
export const GATE_RING = 3;

export function gateRingPlots(data: GameData, tier: number): Record<string, { building: string; level: number }> {
  return { w: { building: 'wall', level: gateRingLevel(data, tier) } };
}

// The walls a road crosses from `fromMs` on: each edge key, with when the
// step past it is done (ms after departure).
export function wallsCrossed(path: readonly PathStep[], walls: ReadonlyMap<string, unknown>, fromMs = 0): { key: string; atMs: number }[] {
  const out: { key: string; atMs: number }[] = [];
  for (let i = 1; i < path.length; i++) {
    const step = path[i]!;
    if (step.atMs < fromMs) continue;
    const key = edgeKey(hex(path[i - 1]!.q, path[i - 1]!.r), hex(step.q, step.r));
    if (walls.has(key)) out.push({ key, atMs: step.atMs });
  }
  return out;
}
