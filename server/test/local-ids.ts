// The local engine's ids (docs/local-engine.md): fixtures recorded on the
// server swap the database's ids for the ones a solo world uses on the
// device: the world -1, the player 1, villages, waves and sites numbered
// from 1 in the order they were made.
export interface LocalIdMaps {
  world: Map<number, number>;
  account: Map<number, number>;
  village: Map<number, number>;
  wave: Map<number, number>;
  site: Map<number, number>;
}

export function idMapsFrom(view: Record<string, unknown>): LocalIdMaps {
  const maps: LocalIdMaps = { world: new Map([[view.id as number, -1]]), account: new Map(), village: new Map(), wave: new Map(), site: new Map() };
  for (const [i, m] of (view.members as { accountId: number }[]).entries()) maps.account.set(m.accountId, i + 1);
  for (const [i, v] of (view.villages as { id: number }[]).entries()) maps.village.set(v.id, i + 1);
  for (const [i, w] of (view.waves as { id: number }[]).entries()) maps.wave.set(w.id, i + 1);
  for (const [i, s] of (view.sites as { id: number }[]).entries()) maps.site.set(s.id, i + 1);
  return maps;
}

const CONTEXT: Record<string, keyof LocalIdMaps> = { villages: 'village', village: 'village', waves: 'wave', wave: 'wave', sites: 'site', members: 'account' };

export function toLocalIds(value: unknown, maps: LocalIdMaps): unknown {
  const keyed: Record<string, Map<number, number>> = {
    worldId: maps.world,
    accountId: maps.account, ownerAccountId: maps.account, hostAccountId: maps.account, exploredBy: maps.account,
    villageId: maps.village, homeVillageId: maps.village, targetVillageId: maps.village,
    waveId: maps.wave,
    siteId: maps.site,
  };
  const walk = (node: unknown, context: keyof LocalIdMaps | null): unknown => {
    if (Array.isArray(node)) return node.map((x) => walk(x, context));
    if (node && typeof node === 'object') {
      const out: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(node)) {
        if (k === 'id' && typeof v === 'number' && context) out[k] = maps[context].get(v) ?? v;
        else if (typeof v === 'number' && keyed[k]) out[k] = keyed[k].get(v) ?? v;
        else if (k === 'inviteCode') out[k] = null;
        else out[k] = walk(v, CONTEXT[k] ?? null);
      }
      return out;
    }
    return node;
  };
  return walk(value, 'world');
}
