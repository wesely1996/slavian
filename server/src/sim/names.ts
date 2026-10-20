// Names for new towns (data/names.json): a town started or founded without a
// name of its own gets one of the old Slavic town names not yet used in its
// world, or else a root and an ending joined ("Bel" + "grad"), never twice in
// one world. `rng` keeps the pick steady for a world's seed.
import type { GameData } from '../data/index.js';

export function townName(data: GameData, taken: Iterable<string>, rng: () => number): string {
  const used = new Set([...taken].map((n) => n.toLowerCase()));
  const free = data.names.whole.filter((n) => !used.has(n.toLowerCase()));
  if (free.length) return free[Math.floor(rng() * free.length)]!;
  const { roots, endings } = data.names;
  for (let tries = 0; tries < 200; tries++) {
    const root = roots[Math.floor(rng() * roots.length)]!;
    const ending = endings[Math.floor(rng() * endings.length)]!;
    // "Bel" + "grad", "Dobro" + "gost"; a root ending in a vowel loses it
    // before an ending that starts with one ("Lipo" + "ets" = "Lipets").
    const name = /[aeiouy]$/.test(root) && /^[aeiouy]/.test(ending) ? root.slice(0, -1) + ending : root + ending;
    if (!used.has(name.toLowerCase())) return name;
  }
  return `${roots[0]}${endings[0]} ${used.size + 1}`;
}

// The default names older servers gave ("Mila's village", "Mila's village 2").
export function isDefaultName(name: string): boolean {
  return /'s village( \d+)?$/.test(name);
}
