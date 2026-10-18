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
