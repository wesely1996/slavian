# Slavian

A cooperative PvE hex-map strategy game for small groups of busy adults: defend the Holy City and build the Kalinov Bridge. Android first. The full design is in [PLAN.md](PLAN.md).

## Layout

| Path | What |
|---|---|
| `client/` | Godot 4.5 project (Android first) |
| `server/` | Node + TypeScript game server: API, live updates, simulation, scheduler |
| `data/` | Shared game data (JSON) and cross-language test fixtures |
| `ops/` | Local dev / deployment config |

## Play it

**Playtest with friends anywhere:** server on your computer, database on Neon, public HTTPS address through a Cloudflare quick tunnel — see [docs/playtest.md](docs/playtest.md).

**Same Wi-Fi only:**

1. Run the server and its database on a computer your phone can reach (same Wi-Fi):
   ```sh
   docker compose -f ops/docker-compose.yml up -d --build
   ```
2. Install the latest dev build APK (see Releases) on your phone.
3. In the app, set **Server address** to `http://<that computer's LAN IP>:8080`, enter a name and tap **Play as guest**.
4. Create a world and share its invite code; teammates tap **Join**. The host taps **Start the world**.

Pick **Test (10×)** speed to see builds finish quickly.

## Server

Requires Node 22+ and PostgreSQL 16 (`docker compose -f ops/docker-compose.yml up -d postgres` gives you one).

```sh
cd server
npm install
npm run typecheck
npm test                                    # unit tests; DB tests skip without TEST_DATABASE_URL
TEST_DATABASE_URL=postgres://slavian:slavian@localhost:5432/slavian npm test

export DATABASE_URL=postgres://slavian:slavian@localhost:5432/slavian
npm run migrate
npm start        # API + live updates + scheduler worker on :8080 (runs migrations on start)
npm run demo     # creates a 100x-speed world, queues builds, lets the scheduler finish them
npm run worker   # standalone scheduler worker (with INLINE_WORKER=0 on the API)
```

### Headless simulator

`npm run sim` plays whole worlds with scripted bots against the real rules, scheduler and database on a simulated clock (use a database of its own: it leaves its worlds behind), and reports how each run went: won, lost or unfinished, the bridge stage and the quests it waited on, Sanctity, villages, hordes beaten.

```sh
DATABASE_URL=postgres://slavian:slavian@localhost:5432/slavian_sim npm run sim -- --players 2 --bots balanced,turtle --difficulty normal --runs 3
```

Options: `--players 1-6`, `--bots` (`turtle`, `expander`, `balanced`, cycled over the players), `--difficulty` (`story`, `normal`, `hard`, `nightmare`), `--runs`, `--speed` (world speed, default 20), `--days` (game days before giving up, default 45), `--json` (one JSON line per run), `--verbose` (a line per game day and the most common refused orders). Bots build, keep a garrison, explore sites, clear camps, found villages, tithe to the bridge and chase its quests; refused orders are normal and only counted.

### API (v1)

| Method | Path | |
|---|---|---|
| `POST` | `/v1/auth/guest` | Create a guest account → `{ token, account }`. Send `Authorization: Bearer <token>` afterwards. |
| `GET` / `PATCH` | `/v1/me` | Your account and worlds / rename. |
| `GET` | `/v1/data` | Game data (buildings, terrain, units, enemies, wave, scouting, battle, logistics, expansion, research, hero and standing-order settings). |
| `POST` | `/v1/worlds` | Create a world (lobby) with an invite code: `{ name, maxPlayers, speed, difficulty }` (`story`, `normal`, `hard` or `nightmare`). |
| `PUT` | `/v1/worlds/:id/quiet` | Host only: the group's quiet hours `{ start, end, utcOffsetMinutes }` (minutes after local midnight; `null` start/end: none). Hordes arriving inside them wait until they end. |
| `POST` | `/v1/worlds/join` | Join by invite code. |
| `GET` | `/v1/worlds/:id` | Full world: members, villages, announced waves, scout missions and reports, recent battles, map, the Kalinov Bridge, `ritualAt` (when Ritual Night's hordes set out) and, once a run is won or lost, `endedAt` and a `run` summary. A finished run stays readable; every command in it answers "This run is over". |
| `POST` | `/v1/worlds/:id/start` | Host only: generate the map and found everyone's village. |
| `POST` | `/v1/villages/:id/build` | Build on a plot: `{ plot }` upgrades what stands there (fields `f0`…`f11`, center slots `c0`…`c11`, outposts `o<q>,<r>`), `{ plot, building }` constructs in an empty slot. `{ building }` alone picks the plot. |
| `POST` | `/v1/villages/:id/outposts` | Claim the resource hex `{ q, r }` (within 2 hexes) and start building an outpost there. |
| `POST` | `/v1/villages/:id/outposts/abandon` | Give up the outpost on `{ q, r }`. |
| `POST` | `/v1/villages/:id/orders` | Place a standing order: `{ kind: "train", unit, batch, target }`, `{ kind: "rebuild" }` or `{ kind: "surplus", share }`. It runs at once, then every 20 game minutes. `POST /v1/villages/:id/orders/:orderId/cancel` stops it. |
| `POST` | `/v1/villages/:id/armies` | Send `{ targetVillageId, units, orders }` (`support`, `reinforce` or `harass`) as an army, or `{ target: { q, r }, units, orders: "hold", withHero? }` to hold a hex (field battles), or `orders: "clear"` with a camp's hex to storm it, or `orders: "explore"` with an ancient site's hex (scouts may go) to search it. `POST /v1/armies/:id/recall` calls a supporting or holding army home. |
| `POST` | `/v1/villages/:id/rebuild` | Rebuild a razed village (pays a share of what stood; done after the rebuild time). |
| `POST` | `/v1/villages/:id/forts` | Build a fort `{ q, r }` within range of the village, paid from its stores. |
| `PUT` | `/v1/villages/:id/reinforce` | How the village answers battles nearby: `{ share, range }` (share 0 stays out). |
| `POST` | `/v1/villages/:id/research` | Start researching `{ tech }` in the village's Academy (one tech at a time per player; effects reach all your villages). |
| `POST` | `/v1/villages/:id/found` | Send 3 settlers to found a village on `{ q, r, name? }`: settleable, within 6 hexes, at least 3 from every village and 2 from the Holy City. |
| `POST` | `/v1/villages/:id/caravans` | Send `{ destinationVillageId, load: { wood, stone, grain, iron } }` by caravan; `destinationVillageId: null` is the Holy City vault. Needs a Caravan Yard (1 caravan per level, 500 each). An optional `escort: { unit: count }` guards it against camps on the road. |
| `POST` | `/v1/villages/:id/caravans/fetch` | Send empty caravans to bring `{ load }` back from the vault. |
| `POST` | `/v1/worlds/:id/hero/move` · `/skills` · `/equip` · `/unequip` · `/rename` | Your hero: travel to `{ villageId }` (one of yours), learn `{ skill }`, wear `{ item }`, take off `{ slot }`, rename `{ name }`. |
| `GET` · `POST` | `/v1/worlds/:id/notifications` · `/notifications/read` | Your inbox in a world (newest first, unread count) / mark it read. |
| `GET` · `PATCH` | `/v1/me/notifications` | Quiet hours `{ quietStart, quietEnd }` (minutes after local midnight, or null), `utcOffsetMinutes`, `digestHour`. |
| `POST` | `/v1/me/devices` | Register a phone's push token `{ token, platform }` (see [docs/push.md](docs/push.md)). |
| `POST` | `/v1/worlds/:id/vault/upgrade` | Enlarge the vault, paid from the vault. |
| `PUT` | `/v1/worlds/:id/clan` | Pick your clan `{ clan }` (`data/clans.json`): freely in the lobby; once the run has started, only if you have none yet. |
| `PUT` | `/v1/worlds/:id/delegation` | Hand your villages to a teammate `{ to: accountId, days: 1–7 }`; they command them as their own, and what they do is logged (`delegations` and `delegationLog` in the world view). |
| `DELETE` | `/v1/worlds/:id/delegation` | End a hand-over: your own, or `{ owner }` to hand a teammate's villages back. |
| `POST` | `/v1/worlds/:id/bridge/donate` | Give `{ resources: { wood, stone, grain, iron }, embers }` from the vault and the group's Embers to the Kalinov Bridge stage being built; capped at what it still needs. |
| `POST` | `/v1/worlds/:id/bridge/ritual` | Forge the ritual torc (spends Embers) for a stage whose quest asks for it. |
| `POST` | `/v1/villages/:id/train` | Train `{ unit, count }` units (needs the unit's building). |
| `POST` | `/v1/villages/:id/scout` | Send `{ waveId, count }` scouts at a wave; the report is shared with the group. |
| `POST` | `/v1/villages/:id/stance` | Set the garrison's battle stance: `defensive`, `balanced`, `offensive` or `hold_the_line`. |
| `GET` | `/v1/live` | WebSocket. Send `{"type":"subscribe","worldId":1}`; receive `village` / `world` / `waves` / `scouting` / `battles` / `raids` / `caravans` (caravans and the vault) / `expeditions` (settlers) / `research` / `heroes` / `orders` / `armies` (armies and forts) updates, and your own `notifications`. |

## Client

Open `client/` in Godot 4.5 and run it with a server running (see above). On the map: drag to pan, pinch or mouse wheel to zoom, tap a hex to inspect it. **Village** (top bar) opens your village: tap a field or slot to build or upgrade it. Tap a forest, plains, hills, mountain or lake hex near your village to claim an outpost.

Headless tests:

```sh
godot --headless --path client --import
godot --headless --path client --script res://tests/test_runner.gd
```

### Android

Install the Android export templates and SDK as described in the [Godot docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html), then use the **Android** preset (`export_presets.cfg`, arm64, package `com.slavian.game`), or enable one-click deploy to run it on a connected phone.

From the command line: `ops/export-android.sh build/slavian-debug.apk` (see the script header for the environment it needs).

## Workflow and CI/CD

All changes go on a feature branch and are merged into `main` through a pull request, which is squash-merged; the branch is deleted after merging.

| Workflow | When | What |
|---|---|---|
| `ci.yml` | Every pull request | Server typecheck + tests (with Postgres), server Docker image smoke test, client tests + smoke run, then a debug APK uploaded as a run artifact (kept 7 days). |
| `dev-build.yml` | Every push to `main` (i.e. merged PRs), or manually | Runs CI, then publishes the APK as a **dev pre-release** tagged `dev-<date>-<sha>`. |
| `cleanup-dev-builds.yml` | Daily at 03:17 UTC, or manually | Deletes dev pre-releases (and their tags) older than 7 days, always keeping the newest one. A manual run can change the age or do a dry run. |

To test a build on a phone, open the latest **Dev build** under Releases and install the APK (allow installs from unknown sources).

### One-time repository setup

1. **Default branch:** `main` (scheduled workflows only run from the default branch).
2. **Merging** (*Settings → General → Pull Requests*): allow only **squash merging** and turn on **Automatically delete head branches**.
3. **Branch protection on `main`:** require a pull request and the `Server tests`, `Server image`, `Client tests` and `Android debug APK` checks.
4. **Signing key secret** (so each dev build installs over the previous one). Create a keystore once and keep a copy safe:
   ```sh
   keytool -genkeypair -keystore slavian-debug.keystore -storepass android -keypass android \
     -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Slavian Debug"
   base64 -w0 slavian-debug.keystore   # paste into the secret below
   ```
   Add it under *Settings → Secrets and variables → Actions* as `ANDROID_DEBUG_KEYSTORE_BASE64`. `ANDROID_DEBUG_KEYSTORE_USER` / `ANDROID_DEBUG_KEYSTORE_PASSWORD` are optional (defaults `androiddebugkey` / `android`). Without the secret, builds still work but use a throwaway key, so you must uninstall before installing a newer build.
