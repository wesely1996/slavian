import websocket from '@fastify/websocket';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { z, ZodError } from 'zod';
import {
  abandonOutpostCommand,
  claimOutpostCommand,
  queueBuildCommand,
  sendScoutsCommand,
  setStanceCommand,
  trainUnitsCommand,
} from '../commands/village.js';
import { STANCES } from '../data/index.js';
import { createWorldCommand, joinWorldCommand, startWorldCommand } from '../commands/worlds.js';
import { accountForToken, createGuestAccount, renameAccount, type Account } from '../db/accounts.js';
import { inTransaction, type Db } from '../db/pool.js';
import { getWorld, isMember, listWorldsForAccount } from '../db/worlds.js';
import { ForbiddenError, NotFoundError, RuleError, UnauthorizedError } from '../errors.js';
import type { SchedulerDeps } from '../scheduler/events.js';
import { InsufficientResourcesError } from '../sim/resources.js';
import type { LiveHub } from './live.js';
import { missionView, villageView, worldSummary, worldView } from './views.js';

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
const hexBody = z.object({ q: z.number().int().min(-999).max(999), r: z.number().int().min(-999).max(999) });
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
      ...(await worldView(client, await getWorld(client, worldId))),
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

  app.post('/v1/worlds', async (request) => {
    const account = await authenticate(db, request);
    const body = createWorldBody.parse(request.body);
    const world = await createWorldCommand(db, { account, ...body });
    return fullWorldView(world.id);
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
