// Hex grid math: axial coordinates (q, r), pointy-top layout, y grows downward.
// Reference: https://www.redblobgames.com/grids/hexagons/

export interface Hex {
  readonly q: number;
  readonly r: number;
}

export interface Point {
  readonly x: number;
  readonly y: number;
}

// Normalises -0 to 0 so keys and equality behave.
export function hex(q: number, r: number): Hex {
  return { q: q + 0, r: r + 0 };
}

// E, NE, NW, W, SW, SE
export const DIRECTIONS: readonly Hex[] = [
  hex(1, 0),
  hex(1, -1),
  hex(0, -1),
  hex(-1, 0),
  hex(-1, 1),
  hex(0, 1),
];

export function hexKey(h: Hex): string {
  return `${h.q},${h.r}`;
}

export function hexEquals(a: Hex, b: Hex): boolean {
  return a.q === b.q && a.r === b.r;
}

export function hexAdd(a: Hex, b: Hex): Hex {
  return hex(a.q + b.q, a.r + b.r);
}

export function hexScale(h: Hex, k: number): Hex {
  return hex(h.q * k, h.r * k);
}

export function hexDistance(a: Hex, b: Hex): number {
  const dq = a.q - b.q;
  const dr = a.r - b.r;
  return (Math.abs(dq) + Math.abs(dr) + Math.abs(dq + dr)) / 2;
}

export function neighbors(h: Hex): Hex[] {
  return DIRECTIONS.map((d) => hexAdd(h, d));
}

export function ring(center: Hex, radius: number): Hex[] {
  if (radius === 0) return [center];
  const result: Hex[] = [];
  // Start at the SW corner and walk the six sides.
  let current = hexAdd(center, hexScale(DIRECTIONS[4]!, radius));
  for (const dir of DIRECTIONS) {
    for (let step = 0; step < radius; step++) {
      result.push(current);
      current = hexAdd(current, dir);
    }
  }
  return result;
}

export function spiral(center: Hex, radius: number): Hex[] {
  const result: Hex[] = [];
  for (let k = 0; k <= radius; k++) result.push(...ring(center, k));
  return result;
}

const SQRT3 = Math.sqrt(3);

export function hexToPixel(h: Hex, size: number): Point {
  return {
    x: size * (SQRT3 * h.q + (SQRT3 / 2) * h.r),
    y: size * 1.5 * h.r,
  };
}

export function hexRound(q: number, r: number): Hex {
  const s = -q - r;
  let rq = Math.round(q);
  let rr = Math.round(r);
  const rs = Math.round(s);
  const dq = Math.abs(rq - q);
  const dr = Math.abs(rr - r);
  const ds = Math.abs(rs - s);
  if (dq > dr && dq > ds) rq = -rr - rs;
  else if (dr > ds) rr = -rq - rs;
  return hex(rq, rr);
}

export function pixelToHex(p: Point, size: number): Hex {
  const q = ((SQRT3 / 3) * p.x - p.y / 3) / size;
  const r = ((2 / 3) * p.y) / size;
  return hexRound(q, r);
}

// Cost of stepping from one hex onto a neighbour; null means impassable.
export type StepCost = (from: Hex, to: Hex) => number | null;

// A* over the hex graph. `minStepCost` must not exceed the cheapest possible
// step or the heuristic stops being admissible.
export function findPath(
  start: Hex,
  goal: Hex,
  stepCost: StepCost,
  minStepCost = 1,
  maxExpanded = 10_000,
): Hex[] | null {
  const startKey = hexKey(start);
  const goalKey = hexKey(goal);
  const open = new MinHeap<Hex>();
  const cameFrom = new Map<string, Hex>();
  const costSoFar = new Map<string, number>([[startKey, 0]]);
  open.push(start, 0);

  let expanded = 0;
  while (open.size > 0) {
    const current = open.pop()!;
    const currentKey = hexKey(current);
    if (currentKey === goalKey) return reconstruct(cameFrom, start, goal);
    if (++expanded > maxExpanded) return null;

    const currentCost = costSoFar.get(currentKey)!;
    for (const next of neighbors(current)) {
      const step = stepCost(current, next);
      if (step === null) continue;
      const nextKey = hexKey(next);
      const newCost = currentCost + step;
      const known = costSoFar.get(nextKey);
      if (known === undefined || newCost < known) {
        costSoFar.set(nextKey, newCost);
        cameFrom.set(nextKey, current);
        open.push(next, newCost + hexDistance(next, goal) * minStepCost);
      }
    }
  }
  return null;
}

function reconstruct(cameFrom: Map<string, Hex>, start: Hex, goal: Hex): Hex[] {
  const path = [goal];
  let current = goal;
  while (!hexEquals(current, start)) {
    current = cameFrom.get(hexKey(current))!;
    path.push(current);
  }
  return path.reverse();
}

class MinHeap<T> {
  private items: { value: T; priority: number }[] = [];

  get size(): number {
    return this.items.length;
  }

  push(value: T, priority: number): void {
    const items = this.items;
    items.push({ value, priority });
    let i = items.length - 1;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (items[parent]!.priority <= items[i]!.priority) break;
      [items[parent], items[i]] = [items[i]!, items[parent]!];
      i = parent;
    }
  }

  pop(): T | undefined {
    const items = this.items;
    const top = items[0];
    const last = items.pop();
    if (items.length > 0 && last) {
      items[0] = last;
      let i = 0;
      for (;;) {
        const left = 2 * i + 1;
        const right = left + 1;
        let smallest = i;
        if (left < items.length && items[left]!.priority < items[smallest]!.priority) smallest = left;
        if (right < items.length && items[right]!.priority < items[smallest]!.priority) smallest = right;
        if (smallest === i) break;
        [items[smallest], items[i]] = [items[i]!, items[smallest]!];
        i = smallest;
      }
    }
    return top?.value;
  }
}
