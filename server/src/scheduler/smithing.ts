// The Blacksmith's work done (data/smithing.json): the unit's line is a
// level better, for all the player's villages and armies.
import { z } from 'zod';
import { notifyWorld } from '../db/notify.js';
import { listMembers, setSmithing } from '../db/worlds.js';
import type { HandlerRegistry } from './events.js';
import { tell } from './notices.js';
import { refreshBonuses } from './research.js';
import { isAffliction } from '../sim/smithing.js';

const smithPayload = z.object({ accountId: z.number().int() });

export const smithingHandlers: HandlerRegistry = {
  async smith_done({ client, data, world }, event) {
    const { accountId } = smithPayload.parse(event.payload);
    const member = (await listMembers(client, world.id)).find((m) => m.accountId === accountId);
    const work = member?.smithWork;
    if (!member || !work || new Date(work.completesAt).getTime() !== event.dueAt.getTime()) return;
    const smithing = { ...member.smithing, [work.unit]: { ...(member.smithing[work.unit] ?? {}), [work.line]: work.level } };
    await setSmithing(client, world.id, accountId, smithing, null);
    await refreshBonuses(client, data, world, [accountId], event.dueAt);
    await tell(client, world, accountId, {
      kind: 'build_done',
      tier: 'digest',
      title: 'The Blacksmith finished: {unit}, {line} {level}',
      body: isAffliction(work.line) ? '{line} for every {unit} of yours from now on.' : '{line} for every {unit} of yours: +{share}% from now on.',
      vars: { unit: data.units.units[work.unit]?.name ?? work.unit, line: data.smithing.lines[work.line].name, level: work.level, share: Math.round(work.level * data.smithing.perLevel * 100) },
    }, event.dueAt);
    await notifyWorld(client, { worldId: world.id, type: 'world' });
  },
};
