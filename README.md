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

### API (v1)

| Method | Path | |
|---|---|---|
| `POST` | `/v1/auth/guest` | Create a guest account → `{ token, account }`. Send `Authorization: Bearer <token>` afterwards. |
| `GET` / `PATCH` | `/v1/me` | Your account and worlds / rename. |
| `GET` | `/v1/data` | Game data (buildings, terrain, units, enemies, wave, scouting and battle settings). |
| `POST` | `/v1/worlds` | Create a world (lobby) with an invite code. |
| `POST` | `/v1/worlds/join` | Join by invite code. |
| `GET` | `/v1/worlds/:id` | Full world: members, villages, announced waves, scout missions and reports, recent battles, map. |
| `POST` | `/v1/worlds/:id/start` | Host only: generate the map and found everyone's village. |
| `POST` | `/v1/villages/:id/build` | Queue a building upgrade. |
| `POST` | `/v1/villages/:id/train` | Train `{ unit, count }` units (needs the unit's building). |
| `POST` | `/v1/villages/:id/scout` | Send `{ waveId, count }` scouts at a wave; the report is shared with the group. |
| `POST` | `/v1/villages/:id/stance` | Set the garrison's battle stance: `defensive`, `balanced`, `offensive` or `hold_the_line`. |
| `GET` | `/v1/live` | WebSocket. Send `{"type":"subscribe","worldId":1}`; receive `village` / `world` / `waves` / `scouting` / `battles` updates. |

## Client

Open `client/` in Godot 4.5 and run it with a server running (see above). On the map: drag to pan, pinch or mouse wheel to zoom, tap a hex to inspect it; tap your village (gold) to build.

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
