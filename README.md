# Slavian

A cooperative PvE hex-map strategy game for small groups of busy adults: defend the Holy City and build the Kalinov Bridge. Android first. The full design is in [PLAN.md](PLAN.md).

## Layout

| Path | What |
|---|---|
| `client/` | Godot 4.5 project (Android first) |
| `server/` | Node + TypeScript simulation, scheduler and (later) API |
| `data/` | Shared game data (JSON) and cross-language test fixtures |
| `ops/` | Local dev / deployment config |

## Server

Requires Node 22+ and PostgreSQL 16 (`docker compose -f ops/docker-compose.yml up -d` gives you one).

```sh
cd server
npm install
npm run typecheck
npm test                                    # unit tests; DB tests skip without TEST_DATABASE_URL
TEST_DATABASE_URL=postgres://slavian:slavian@localhost:5432/slavian npm test

export DATABASE_URL=postgres://slavian:slavian@localhost:5432/slavian
npm run migrate
npm run demo     # creates a 100x-speed world, queues builds, lets the scheduler finish them
npm run worker   # long-running scheduler worker
```

## Client

Open `client/` in Godot 4.5. The main scene is the M0 map spike: drag to pan, pinch or mouse wheel to zoom, tap a hex to inspect it, and use the top buttons to preview maps for 1–6 players.

Headless tests:

```sh
godot --headless --path client --import
godot --headless --path client --script res://tests/test_runner.gd
```

### Android

Install the Android export templates and SDK as described in the [Godot docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html), then use the **Android** preset (`export_presets.cfg`, arm64, package `com.slavian.game`), or enable one-click deploy to run it on a connected phone.

From the command line: `ops/export-android.sh build/slavian-debug.apk` (see the script header for the environment it needs).

## Workflow and CI/CD

All changes go on a feature branch and are merged into `main` through a pull request.

| Workflow | When | What |
|---|---|---|
| `ci.yml` | Every pull request | Server typecheck + tests (with Postgres), client tests + smoke run, then a debug APK uploaded as a run artifact (kept 7 days). |
| `dev-build.yml` | Every push to `main` (i.e. merged PRs), or manually | Runs CI, then publishes the APK as a **dev pre-release** tagged `dev-<date>-<sha>`. |
| `cleanup-dev-builds.yml` | Daily at 03:17 UTC, or manually | Deletes dev pre-releases (and their tags) older than 7 days, always keeping the newest one. A manual run can change the age or do a dry run. |

To test a build on a phone, open the latest **Dev build** under Releases and install the APK (allow installs from unknown sources).

### One-time repository setup

1. **Default branch:** `main` (scheduled workflows only run from the default branch).
2. **Branch protection on `main`:** require a pull request and the `Server tests`, `Client tests` and `Android debug APK` checks.
3. **Signing key secret** (so each dev build installs over the previous one). Create a keystore once and keep a copy safe:
   ```sh
   keytool -genkeypair -keystore slavian-debug.keystore -storepass android -keypass android \
     -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Slavian Debug"
   base64 -w0 slavian-debug.keystore   # paste into the secret below
   ```
   Add it under *Settings → Secrets and variables → Actions* as `ANDROID_DEBUG_KEYSTORE_BASE64`. `ANDROID_DEBUG_KEYSTORE_USER` / `ANDROID_DEBUG_KEYSTORE_PASSWORD` are optional (defaults `androiddebugkey` / `android`). Without the secret, builds still work but use a throwaway key, so you must uninstall before installing a newer build.
