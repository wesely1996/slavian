// Live updates over WebSocket. Clients subscribe to a world; whenever a
// world_events notification arrives (from this process or the scheduler
// worker), the changed village or world is pushed to every subscriber.
//
// Client -> server: { "type": "subscribe", "worldId": 1 }
// Server -> client: { "type": "subscribed", "worldId", "serverTime" }
//                   { "type": "village", "village", "serverTime" }
//                   { "type": "world", "world", "serverTime" }
//                   { "type": "waves", "worldId", "waves", "serverTime" }
//                   { "type": "scouting", "worldId", "missions", "serverTime" }
//                   { "type": "battles", "worldId", "battles", "serverTime" }
//                   { "type": "raids", "worldId", "raids", "serverTime" }
//                   { "type": "caravans", "worldId", "caravans", "vault", "serverTime" }
//                   { "type": "expeditions", "worldId", "expeditions", "serverTime" }
//                   { "type": "research", "worldId", "research", "serverTime" }
//                   { "type": "heroes", "worldId", "heroes", "serverTime" }
//                   { "type": "orders", "worldId", "orders", "serverTime" }
//                   { "type": "notifications", "worldId", "notifications", "unread", "serverTime" } (yours only)
//                   { "type": "error", "message" }
import type { WebSocket } from 'ws';
import { z } from 'zod';
import type { Account } from '../db/accounts.js';
import { worldEventsChannel, type WorldEvent } from '../db/notify.js';
import { inTransaction, type Db, type DbClient } from '../db/pool.js';
import { loadVillage } from '../db/villages.js';
import { getWorld, isMember } from '../db/worlds.js';
import type { GameData } from '../data/index.js';
import { battlesView, expeditionsView, heroesView, inboxView, ordersView, logisticsView, researchListView, raidsView, scoutingView, villageView, wavesView, worldView } from './views.js';

const clientMessage = z.object({ type: z.literal('subscribe'), worldId: z.number().int().positive() });
const RECONNECT_MS = 2000;

export class LiveHub {
  private readonly subscribers = new Map<number, Set<WebSocket>>();
  private readonly owners = new WeakMap<WebSocket, number>();
  private listener: DbClient | null = null;
  private channel = '';
  private stopped = false;

  constructor(
    private readonly db: Db,
    private readonly data: GameData,
    private readonly clock: () => Date = () => new Date(),
  ) {}

  async start(): Promise<void> {
    this.stopped = false;
    const client = await this.db.connect();
    this.channel = await worldEventsChannel(client);
    client.on('notification', (message) => {
      if (message.channel !== this.channel || !message.payload) return;
      void this.dispatch(JSON.parse(message.payload) as WorldEvent);
    });
    client.on('error', (error) => {
      console.error('Live listener connection failed:', error);
      this.listener = null;
      client.release(error);
      if (!this.stopped) setTimeout(() => void this.start().catch(console.error), RECONNECT_MS);
    });
    await client.query(`LISTEN ${client.escapeIdentifier(this.channel)}`);
    this.listener = client;
  }

  async stop(): Promise<void> {
    this.stopped = true;
    for (const sockets of this.subscribers.values()) for (const socket of sockets) socket.close(1001, 'Server stopping');
    this.subscribers.clear();
    if (this.listener) {
      await this.listener.query(`UNLISTEN ${this.listener.escapeIdentifier(this.channel)}`).catch(() => {});
      this.listener.release();
      this.listener = null;
    }
  }

  attach(socket: WebSocket, account: Account): void {
    const worlds = new Set<number>();
    this.owners.set(socket, account.id);
    socket.on('message', (raw) => {
      void (async () => {
        const parsed = clientMessage.safeParse(safeJson(raw.toString()));
        if (!parsed.success) return send(socket, { type: 'error', message: 'Unknown message' });
        const { worldId } = parsed.data;
        const member = await inTransaction(this.db, (client) => isMember(client, worldId, account.id));
        if (!member) return send(socket, { type: 'error', message: `World ${worldId} not found` });
        worlds.add(worldId);
        this.socketsFor(worldId).add(socket);
        send(socket, { type: 'subscribed', worldId, serverTime: this.clock().toISOString() });
      })().catch((error) => {
        console.error('Live message failed:', error);
        send(socket, { type: 'error', message: 'Internal server error' });
      });
    });
    socket.on('close', () => {
      for (const worldId of worlds) this.subscribers.get(worldId)?.delete(socket);
    });
  }

  private socketsFor(worldId: number): Set<WebSocket> {
    let sockets = this.subscribers.get(worldId);
    if (!sockets) {
      sockets = new Set();
      this.subscribers.set(worldId, sockets);
    }
    return sockets;
  }

  private async dispatch(event: WorldEvent): Promise<void> {
    const sockets = this.subscribers.get(event.worldId);
    if (!sockets || sockets.size === 0) return;
    if (event.type === 'notifications') return this.dispatchInbox(event.worldId, event.accountId, sockets);
    try {
      const message = await inTransaction(this.db, async (client) => {
        const serverTime = this.clock().toISOString();
        if (event.type === 'village') {
          return { type: 'village', village: villageView(await loadVillage(client, event.villageId)), serverTime };
        }
        if (event.type === 'battles') {
          return { type: 'battles', worldId: event.worldId, battles: await battlesView(client, event.worldId), serverTime };
        }
        if (event.type === 'orders') {
          return { type: 'orders', worldId: event.worldId, orders: await ordersView(client, event.worldId), serverTime };
        }
        if (event.type === 'heroes') {
          return { type: 'heroes', worldId: event.worldId, heroes: await heroesView(client, this.data, event.worldId), serverTime };
        }
        if (event.type === 'research') {
          return { type: 'research', worldId: event.worldId, research: await researchListView(client, event.worldId), serverTime };
        }
        if (event.type === 'expeditions') {
          return { type: 'expeditions', worldId: event.worldId, expeditions: await expeditionsView(client, event.worldId), serverTime };
        }
        if (event.type === 'caravans') {
          return { type: 'caravans', worldId: event.worldId, ...(await logisticsView(client, this.data, event.worldId)), serverTime };
        }
        if (event.type === 'raids') {
          return { type: 'raids', worldId: event.worldId, raids: await raidsView(client, event.worldId), serverTime };
        }
        if (event.type === 'scouting') {
          return { type: 'scouting', worldId: event.worldId, missions: await scoutingView(client, event.worldId), serverTime };
        }
        if (event.type === 'waves') {
          return { type: 'waves', worldId: event.worldId, waves: await wavesView(client, event.worldId), serverTime };
        }
        return { type: 'world', world: await worldView(client, this.data, await getWorld(client, event.worldId)), serverTime };
      });
      for (const socket of sockets) send(socket, message);
    } catch (error) {
      console.error('Live dispatch failed:', error);
    }
  }

  private async dispatchInbox(worldId: number, accountId: number, sockets: Set<WebSocket>): Promise<void> {
    const mine = [...sockets].filter((socket) => this.owners.get(socket) === accountId);
    if (!mine.length) return;
    try {
      const message = await inboxMessage(this.db, worldId, accountId, this.clock().toISOString());
      for (const socket of mine) send(socket, message);
    } catch (error) {
      console.error('Live inbox dispatch failed:', error);
    }
  }
}

// A player's inbox goes to their own sockets only.
async function inboxMessage(db: Db, worldId: number, accountId: number, serverTime: string) {
  return inTransaction(db, async (client) => ({
    type: 'notifications',
    worldId,
    ...(await inboxView(client, accountId, worldId)),
    serverTime,
  }));
}

function send(socket: WebSocket, message: unknown): void {
  if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(message));
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
