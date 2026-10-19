import websocket from '@fastify/websocket';
import { delegateCommand, endDelegationCommand } from '../commands/delegation.js';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { z, ZodError } from 'zod';
import { loadPrefs, markAllRead, registerDevice, savePrefs } from '../db/notifications.js';
import { notifyWorld } from '../db/notify.js';
import { cancelOrderCommand, placeOrderCommand } from '../commands/orders.js';
import { buildCrossingCommand, buildFortCommand, buildRoadCommand, recallArmyCommand, sendArmyCommand, setReinforceCommand } from '../commands/armies.js';
import { equipCommand, learnSkillCommand, moveHeroCommand, renameHeroCommand, unequipCommand } from '../commands/heroes.js';
import type { Hero } from '../db/heroes.js';
import { fetchFromVaultCommand, sendCaravanCommand, upgradeVaultCommand } from '../commands/logistics.js';
import {
  abandonOutpostCommand,
  claimOutpostCommand,
  foundVillageCommand,
  queueBuildCommand,
  rebuildCommand,
  sendScoutsCommand,
  setStanceCommand,
  startResearchCommand,
  trainUnitsCommand,
} from '../commands/village.js';
import { DIFFICULTIES, HERO_SLOTS, STANCES } from '../data/index.js';
import { createWorldCommand, joinWorldCommand, setClanCommand, setQuietHoursCommand, startWorldCommand } from '../commands/worlds.js';
import { craftRitualCommand, donateCommand } from '../scheduler/bridge.js';
import { accountForToken, createGuestAccount, renameAccount, type Account } from '../db/accounts.js';
import { inTransaction, type Db } from '../db/pool.js';
import { getWorld, isMember, listWorldsForAccount } from '../db/worlds.js';
import { ForbiddenError, NotFoundError, RuleError, UnauthorizedError } from '../errors.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { InsufficientResourcesError } from '../sim/resources.js';
import type { LiveHub } from './live.js';
import {
  armyView,
  caravanView,
  expeditionView,
  heroView,
  inboxView,
  orderView,
  researchView,
  missionView,
  vaultView,
  villageView,
  worldSummary,
  worldView,
  fortView,
} from './views.js';

export interface AppDeps {
  db: Db;
  scheduler: SchedulerDeps;
  clock: () => Date;
  live?: LiveHub;
  logger?: boolean;
}

const displayName = z.string().trim().min(1).max(32);
const idParams = z.object({ id: z.coerce.number().int().positive() });

const guestBody = z.object({ displayName: displayName.optional() }).default({});
const renameBody = z.object({ displayName });
const createWorldBody = z.object({
  name: z.string().trim().min(1).max(48),
  maxPlayers: z.number().int().min(1).max(6).default(6),
  speed: z.number().min(1).max(100).default(1),
  difficulty: z.enum(DIFFICULTIES).default('normal'),
});
const joinWorldBody = z.object({ inviteCode: z.string().min(1).max(16) });
// `plot` targets a field, center slot or outpost ("o3,-2"); `building`
// names what to construct in an empty slot. Older clients send only
// `building`.
const buildBody = z
  .object({
    plot: z.string().regex(/^([fc]\d{1,2}|o-?\d{1,3},-?\d{1,3})$/).optional(),
    building: z.string().min(1).max(64).optional(),
  })
  .refine((body) => body.plot || body.building, { message: 'Give a plot or a building' });
const trainBody = z.object({ unit: z.string().min(1).max(64), count: z.number().int().positive() });
const stanceBody = z.object({ stance: z.enum(STANCES) });
const amount = z.number().int().min(0).max(1_000_000);
const loadSchema = z.object({ wood: amount, stone: amount, grain: amount, iron: amount });
// No destination: the Holy City vault.
const escortSchema = z.record(z.string().max(64), z.number().int().min(0).max(100_000)).optional();
const caravanBody = z.object({ destinationVillageId: z.number().int().positive().nullable().default(null), load: loadSchema, escort: escortSchema });
const fetchBody = z.object({ load: loadSchema, escort: escortSchema });
const hexBody = z.object({ q: z.number().int().min(-999).max(999), r: z.number().int().min(-999).max(999) });
const crossingBody = z.object({ a: hexBody, b: hexBody });
const heroMoveBody = z.object({ villageId: z.number().int().positive() });
const heroSkillBody = z.object({ skill: z.string().min(1).max(64) });
const heroEquipBody = z.object({ item: z.string().min(1).max(64) });
const heroUnequipBody = z.object({ slot: z.enum(HERO_SLOTS) });
const heroRenameBody = z.object({ name: displayName });
const orderBody = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('train'), unit: z.string().min(1).max(64), batch: z.number().int(), target: z.number().int() }),
  z.object({ kind: z.literal('rebuild') }),
  z.object({ kind: z.literal('surplus'), share: z.number() }),
]);
const orderParams = z.object({ id: z.coerce.number().int().positive(), orderId: z.coerce.number().int().positive() });
const minuteOfDay = z.number().int().min(0).max(1439);
// From the vault into the bridge's open stage.
const donateBody = z.object({ resources: loadSchema, embers: z.number().int().min(0).max(100).default(0) });
const clanBody = z.object({ clan: z.string().min(1).max(32) });
const delegateBody = z.object({ to: z.number().int().positive(), days: z.number().int() });
const endDelegationBody = z.object({ owner: z.number().int().positive().optional() });
// The group's quiet hours (null start/end: none), set by the host.
const quietBody = z.object({
  start: minuteOfDay.nullable(),
  end: minuteOfDay.nullable(),
  utcOffsetMinutes: z.number().int().min(-14 * 60).max(14 * 60).default(0),
});
const prefsBody = z.object({
  quietStart: minuteOfDay.nullable().optional(),
  quietEnd: minuteOfDay.nullable().optional(),
  utcOffsetMinutes: z.number().int().min(-14 * 60).max(14 * 60).optional(),
  digestHour: z.number().int().min(0).max(23).optional(),
});
const deviceBody = z.object({ token: z.string().min(10).max(4096), platform: z.enum(['android', 'ios', 'web']) });
// A village to go to, or (orders 'hold') a hex to hold.
const armyBody = z.object({
  targetVillageId: z.number().int().positive().nullable().default(null),
  target: hexBody.optional(),
  units: z.record(z.string().max(64), z.number().int().min(0).max(100_000)),
  orders: z.enum(['support', 'reinforce', 'harass', 'hold', 'clear', 'explore']),
  withHero: z.boolean().optional(),
});
const reinforceBody = z.object({ share: z.number().min(0).max(1), range: z.number().int().min(0).max(99) });
const researchBody = z.object({ tech: z.string().min(1).max(64) });
const foundBody = hexBody.extend({ name: z.string().trim().max(32).optional() });
const scoutBody = z.object({ waveId: z.number().int().positive(), count: z.number().int().positive() });

export async function authenticate(db: Db, request: FastifyRequest): Promise<Account> {
  const header = request.headers.authorization ?? '';
  const match = /^Bearer (\S+)$/.exec(header);
  if (!match) throw new UnauthorizedError('Missing bearer token');
  const account = await inTransaction(db, (client) => accountForToken(client, match[1]!));
  if (!account) throw new UnauthorizedError('Invalid token');
  return account;
}

export async function buildApp(deps: AppDeps): Promise<FastifyInstance> {
  const { db, scheduler, clock } = deps;
  const app = Fastify({ logger: deps.logger ?? false });
  await app.register(websocket);

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof ZodError) {
      return reply.status(400).send({ error: 'invalid_request', message: z.prettifyError(error) });
    }
    if (error instanceof InsufficientResourcesError) {
      return reply.status(400).send({ error: 'insufficient_resources', message: error.message, missing: error.missing });
    }
    if (error instanceof RuleError) return reply.status(400).send({ error: 'rule', message: error.message });
    if (error instanceof UnauthorizedError) return reply.status(401).send({ error: 'unauthorized', message: error.message });
    if (error instanceof ForbiddenError) return reply.status(403).send({ error: 'forbidden', message: error.message });
    if (error instanceof NotFoundError) return reply.status(404).send({ error: 'not_found', message: error.message });
    const status = (error as { statusCode?: number }).statusCode;
    if (status && status < 500) return reply.status(status).send({ error: 'bad_request', message: (error as Error).message });
    request.log.error(error);
    return reply.status(500).send({ error: 'internal', message: 'Internal server error' });
  });

  // Non-members get a 404 so world ids cannot be probed.
  async function requireMember(account: Account, worldId: number): Promise<void> {
    const member = await inTransaction(db, (client) => isMember(client, worldId, account.id));
    if (!member) throw new NotFoundError(`World ${worldId} not found`);
  }

  async function fullWorldView(worldId: number) {
    return inTransaction(db, async (client) => ({
      ...(await worldView(client, scheduler.data, await getWorld(client, worldId), clock())),
      serverTime: clock().toISOString(),
    }));
  }

  app.get('/health', async () => ({ ok: true }));

  app.get('/v1/data', async () => ({
    buildings: scheduler.data.buildings,
    terrain: scheduler.data.terrain,
    units: scheduler.data.units,
    enemies: scheduler.data.enemies,
    waves: scheduler.data.waves,
    scouting: scheduler.data.scouting,
    battle: scheduler.data.battle,
    logistics: scheduler.data.logistics,
    expansion: scheduler.data.expansion,
    research: scheduler.data.research,
    heroes: scheduler.data.heroes,
    leaders: scheduler.data.leaders,
    walls: scheduler.data.walls,
    orders: scheduler.data.orders,
    armies: scheduler.data.armies,
    field: scheduler.data.field,
    horde: scheduler.data.horde,
    camps: scheduler.data.camps,
    difficulty: scheduler.data.difficulty,
    sites: scheduler.data.sites,
    lore: scheduler.data.lore,
    bridge: scheduler.data.bridge,
    clans: scheduler.data.clans,
    onboarding: scheduler.data.onboarding,
  }));

  app.post('/v1/auth/guest', async (request) => {
    const body = guestBody.parse(request.body ?? {});
    const name = body.displayName ?? `Guest ${Math.floor(1000 + Math.random() * 9000)}`;
    const { account, token } = await inTransaction(db, (client) => createGuestAccount(client, name));
    return { token, account };
  });

  app.get('/v1/me', async (request) => {
    const account = await authenticate(db, request);
    const worlds = await inTransaction(db, (client) => listWorldsForAccount(client, account.id));
    return { account, worlds: worlds.map(worldSummary) };
  });

  app.patch('/v1/me', async (request) => {
    const account = await authenticate(db, request);
    const body = renameBody.parse(request.body);
    return { account: await inTransaction(db, (client) => renameAccount(client, account.id, body.displayName)) };
  });

  // When to be bothered: quiet hours (local minutes, may wrap midnight),
  // the device's UTC offset and the daily digest hour.
  app.get('/v1/me/notifications', async (request) => {
    const account = await authenticate(db, request);
    return { prefs: await inTransaction(db, (client) => loadPrefs(client, account.id)) };
  });

  app.patch('/v1/me/notifications', async (request) => {
    const account = await authenticate(db, request);
    const body = prefsBody.parse(request.body);
    const prefs = await inTransaction(db, async (client) => {
      const current = await loadPrefs(client, account.id);
      const next = {
        quietStart: body.quietStart === undefined ? current.quietStart : body.quietStart,
        quietEnd: body.quietEnd === undefined ? current.quietEnd : body.quietEnd,
        utcOffsetMinutes: body.utcOffsetMinutes ?? current.utcOffsetMinutes,
        digestHour: body.digestHour ?? current.digestHour,
      };
      await savePrefs(client, account.id, next);
      return next;
    });
    return { prefs };
  });

  // A phone's push token (FCM registration token).
  app.post('/v1/me/devices', async (request) => {
    const account = await authenticate(db, request);
    const body = deviceBody.parse(request.body);
    await inTransaction(db, (client) => registerDevice(client, account.id, body.token, body.platform));
    return { ok: true };
  });

  app.get('/v1/worlds/:id/notifications', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    await requireMember(account, id);
    return { ...(await inTransaction(db, (client) => inboxView(client, account.id, id))), serverTime: clock().toISOString() };
  });

  app.post('/v1/worlds/:id/notifications/read', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    await requireMember(account, id);
    await inTransaction(db, async (client) => {
      await markAllRead(client, account.id, id, clock());
      await notifyWorld(client, { worldId: id, type: 'notifications', accountId: account.id });
    });
    return { ok: true };
  });

  app.post('/v1/worlds', async (request) => {
    const account = await authenticate(db, request);
    const body = createWorldBody.parse(request.body);
    const world = await createWorldCommand(db, { account, ...body });
    return fullWorldView(world.id);
  });

  app.put('/v1/worlds/:id/quiet', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = quietBody.parse(request.body);
    await setQuietHoursCommand(db, { account, worldId: id, ...body });
    return fullWorldView(id);
  });

  app.put('/v1/worlds/:id/clan', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const { clan } = clanBody.parse(request.body);
    await setClanCommand(db, scheduler, { account, worldId: id, clan, now: clock() });
    return fullWorldView(id);
  });

  app.put('/v1/worlds/:id/delegation', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = delegateBody.parse(request.body);
    await delegateCommand(db, scheduler, { accountId: account.id, worldId: id, ...body, now: clock() });
    return fullWorldView(id);
  });

  app.delete('/v1/worlds/:id/delegation', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = endDelegationBody.parse(request.body ?? {});
    await endDelegationCommand(db, scheduler, { accountId: account.id, worldId: id, owner: body.owner, now: clock() });
    return fullWorldView(id);
  });

  app.post('/v1/worlds/:id/bridge/donate', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = donateBody.parse(request.body);
    await donateCommand(db, scheduler, { accountId: account.id, worldId: id, resources: body.resources, embers: body.embers, now: clock() });
    return fullWorldView(id);
  });

  app.post('/v1/worlds/:id/bridge/ritual', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    await craftRitualCommand(db, scheduler, { accountId: account.id, worldId: id, now: clock() });
    return fullWorldView(id);
  });

  app.post('/v1/worlds/join', async (request) => {
    const account = await authenticate(db, request);
    const body = joinWorldBody.parse(request.body);
    const world = await joinWorldCommand(db, { account, inviteCode: body.inviteCode });
    return fullWorldView(world.id);
  });

  app.get('/v1/worlds/:id', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    await requireMember(account, id);
    return fullWorldView(id);
  });

  app.post('/v1/worlds/:id/start', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    await requireMember(account, id);
    await startWorldCommand(db, scheduler, { account, worldId: id, now: clock() });
    return fullWorldView(id);
  });

  app.post('/v1/villages/:id/build', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = buildBody.parse(request.body);
    const { village } = await queueBuildCommand(db, scheduler, {
      accountId: account.id,
      villageId: id,
      ...(body.plot ? { plot: body.plot } : {}),
      ...(body.building ? { building: body.building } : {}),
      now: clock(),
    });
    return { village: villageView(village), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/train', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = trainBody.parse(request.body);
    const { village } = await trainUnitsCommand(db, scheduler, {
      accountId: account.id,
      villageId: id,
      unit: body.unit,
      count: body.count,
      now: clock(),
    });
    return { village: villageView(village), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/scout', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = scoutBody.parse(request.body);
    const { village, mission } = await sendScoutsCommand(db, scheduler, {
      accountId: account.id,
      villageId: id,
      waveId: body.waveId,
      count: body.count,
      now: clock(),
    });
    return { village: villageView(village), mission: missionView(mission), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/stance', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = stanceBody.parse(request.body);
    const { village } = await setStanceCommand(db, scheduler, { accountId: account.id, villageId: id, stance: body.stance, now: clock() });
    return { village: villageView(village), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/outposts', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = hexBody.parse(request.body);
    const { village } = await claimOutpostCommand(db, scheduler, { accountId: account.id, villageId: id, ...body, now: clock() });
    return { village: villageView(village), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/outposts/abandon', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = hexBody.parse(request.body);
    const { village } = await abandonOutpostCommand(db, scheduler, { accountId: account.id, villageId: id, ...body, now: clock() });
    return { village: villageView(village), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/rebuild', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const { village } = await rebuildCommand(db, scheduler, { accountId: account.id, villageId: id, now: clock() });
    return { village: villageView(village), serverTime: clock().toISOString() };
  });

  // The caller's hero in a world.
  async function heroRoute<B>(
    request: FastifyRequest,
    schema: z.ZodType<B>,
    run: (input: { accountId: number; worldId: number; now: Date } & B) => Promise<Hero>,
  ) {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    await requireMember(account, id);
    const hero = await run({ accountId: account.id, worldId: id, now: clock(), ...schema.parse(request.body) });
    return { hero: heroView(scheduler.data, hero), serverTime: clock().toISOString() };
  }
  app.post('/v1/worlds/:id/hero/move', (request) => heroRoute(request, heroMoveBody, (input) => moveHeroCommand(db, scheduler, input)));
  app.post('/v1/worlds/:id/hero/skills', (request) => heroRoute(request, heroSkillBody, (input) => learnSkillCommand(db, scheduler, input)));
  app.post('/v1/worlds/:id/hero/equip', (request) => heroRoute(request, heroEquipBody, (input) => equipCommand(db, scheduler, input)));
  app.post('/v1/worlds/:id/hero/unequip', (request) => heroRoute(request, heroUnequipBody, (input) => unequipCommand(db, scheduler, input)));
  app.post('/v1/worlds/:id/hero/rename', (request) => heroRoute(request, heroRenameBody, (input) => renameHeroCommand(db, scheduler, input)));

  app.post('/v1/villages/:id/orders', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const spec = orderBody.parse(request.body);
    const { village, order } = await placeOrderCommand(db, scheduler, { accountId: account.id, villageId: id, spec, now: clock() });
    return { village: villageView(village), order: orderView(order), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/orders/:orderId/cancel', async (request) => {
    const account = await authenticate(db, request);
    const { id, orderId } = orderParams.parse(request.params);
    await cancelOrderCommand(db, scheduler, { accountId: account.id, villageId: id, orderId, now: clock() });
    return { ok: true, serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/armies', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = armyBody.parse(request.body);
    const army = await sendArmyCommand(db, scheduler, { accountId: account.id, villageId: id, ...body, now: clock() });
    return { army: armyView(army), serverTime: clock().toISOString() };
  });

  app.post('/v1/armies/:id/recall', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const army = await recallArmyCommand(db, scheduler, { accountId: account.id, armyId: id, now: clock() });
    return { army: armyView(army), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/forts', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = hexBody.parse(request.body);
    const fort = await buildFortCommand(db, scheduler, { accountId: account.id, villageId: id, cell: body, now: clock() });
    return { fort: fortView(fort), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/crossings', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = crossingBody.parse(request.body);
    await buildCrossingCommand(db, scheduler, { accountId: account.id, villageId: id, a: body.a, b: body.b, now: clock() });
    const worldId = (await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [id])).rows[0]!.world_id;
    return fullWorldView(Number(worldId));
  });

  app.post('/v1/villages/:id/roads', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = crossingBody.parse(request.body);
    await buildRoadCommand(db, scheduler, { accountId: account.id, villageId: id, a: body.a, b: body.b, now: clock() });
    const worldId = (await db.query<{ world_id: number }>('SELECT world_id FROM villages WHERE id = $1', [id])).rows[0]!.world_id;
    return fullWorldView(Number(worldId));
  });

  app.put('/v1/villages/:id/reinforce', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = reinforceBody.parse(request.body);
    await setReinforceCommand(db, scheduler.data, { accountId: account.id, villageId: id, ...body });
    return { reinforce: body };
  });

  app.post('/v1/villages/:id/research', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = researchBody.parse(request.body);
    const { village, research } = await startResearchCommand(db, scheduler, { accountId: account.id, villageId: id, tech: body.tech, now: clock() });
    return { village: villageView(village), research: researchView(research), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/found', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = foundBody.parse(request.body);
    const { village, expedition } = await foundVillageCommand(db, scheduler, {
      accountId: account.id,
      villageId: id,
      q: body.q,
      r: body.r,
      ...(body.name ? { name: body.name } : {}),
      now: clock(),
    });
    return { village: villageView(village), expedition: expeditionView(expedition), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/caravans', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = caravanBody.parse(request.body);
    const { village, caravan } = await sendCaravanCommand(db, scheduler, { accountId: account.id, villageId: id, ...body, now: clock() });
    return { village: villageView(village), caravan: caravanView(caravan), serverTime: clock().toISOString() };
  });

  app.post('/v1/villages/:id/caravans/fetch', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    const body = fetchBody.parse(request.body);
    const { village, caravan } = await fetchFromVaultCommand(db, scheduler, { accountId: account.id, villageId: id, ...body, now: clock() });
    return { village: villageView(village), caravan: caravanView(caravan), serverTime: clock().toISOString() };
  });

  app.post('/v1/worlds/:id/vault/upgrade', async (request) => {
    const account = await authenticate(db, request);
    const { id } = idParams.parse(request.params);
    await requireMember(account, id);
    const vault = await upgradeVaultCommand(db, scheduler, { worldId: id, now: clock() });
    return { vault: vaultView(scheduler.data, vault), serverTime: clock().toISOString() };
  });

  if (deps.live) {
    const live = deps.live;
    app.get(
      '/v1/live',
      {
        websocket: true,
        preValidation: async (request) => {
          (request as FastifyRequest & { account?: Account }).account = await authenticate(db, request);
        },
      },
      (socket, request) => {
        const account = (request as FastifyRequest & { account?: Account }).account!;
        live.attach(socket, account);
      },
    );
  }

  return app;
}
