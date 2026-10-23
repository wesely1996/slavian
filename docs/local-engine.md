# The local engine (single player on the device)

PLAN.md M5 step 24. A solo world runs entirely in the app, with no calls to
the server. Co-op worlds keep using the server.

## Shape

The local engine is an in-app stand-in for the server. The screens don't
change: they keep calling `Api` and listening to `Live`.

- **Routing:** for a local world, `Api` hands each request to the local
  server (`client/scripts/local/`) instead of the network. It answers with
  the same JSON as the HTTP API. Its changes reach the screens through the
  same signals `Live` emits today.
- **Store:** in memory, the same tables as the database: worlds, members,
  villages, waves, scheduled events, heroes and so on. It is saved as JSON
  under `user://local/<world id>.json` after each command and each scheduler
  pass, and loaded when the world opens.
- **Scheduler:** the same event types as `server/src/scheduler`. Due events
  run in time order when the world opens, so a closed game catches up, and
  from `_process` while it is open.
- **Rules:** `server/src/sim`, `scheduler` and `commands` ported line by
  line to GDScript, with the same names, so a change on one side is easy to
  find on the other.

## Staying the same as the server

- **Fixtures:** `npm run fixtures` (`server/src/fixtures.ts`) writes the
  shared fixtures (`data/fixtures/*-vectors.json`), the bundled game data
  (`client/data/game.json`) and the notice translations
  (`client/data/notices.json`).
  - `server/test/fixtures.test.ts` fails while either is stale.
  - The client test (`client/tests/test_runner.gd`) checks the port against
    the fixtures.
  - After changing a rule or anything in `data/`, run `npm run fixtures`,
    then change the GDScript port until the client test passes.
- **Determinism:** the port reproduces the server's arithmetic, including:
  - 32-bit integer RNG (`LocalRng`);
  - the order of ties in A* (`LocalLand`);
  - JavaScript's `Math.round` (round half up) where the server uses it;
  - V8's comparator call order for `sort`, where a comparator draws
    randomness.
- **Key order:** the server keeps units, plots and the like as jsonb,
  which reads back with keys shortest first, then in byte order, and loops
  over them feed the RNG and sums. `LocalServer.as_stored` puts the world in
  that order before each event and request (as the server loads its rows
  afresh), and code builds dictionaries in the order the server's code
  builds objects.
- **Map order:** the server reads the map by row, then column, and some
  searches settle ties by that order (the nearest spawn hex for scouts).
  The local world keeps its hexes in that order.
- **Ids:** Postgres sequences aren't rolled back. When a server command
  inserts a row and then fails, that id is used up, and the local engine
  skips it too (`world.next`).
- **Precision:** use doubles (`float`) for anything that feeds a decision.
  `Vector2` is single precision.
- **Fixture numbers:** Godot's JSON reader isn't exact in the last digits.
  Store exact values as integers (scaled) or compare with a tolerance.
- **Powers:** V8's `**` and C's `pow` can differ in the last bit. Where a
  power feeds a decision (a threshold, a floor), round it the same way on
  both sides, or check the fixture there with a tolerance.
- **Scenario fixtures:** a server test plays a script of requests and
  waits on a real solo world and records every answer with the local
  engine's ids (`server/test/scenario.ts`, `local-ids.ts`). The client test replays the
  script on a solo world started in the app and compares each answer.
  New rules come with new steps in a scenario. Where play would take too
  long, a `set` step jumps the world ahead (the bridge's state, the group's
  Ember) on both sides.
- **Coverage:** `server/test/parity.test.ts` fails when an API route is
  played by no scenario (unless it's listed as one a solo world never
  calls, with the reason), when a scenario calls a route the server lacks,
  or when no scenario builds on some kind of plot (field, centre, walls,
  tower slot, outpost). A new route or plot kind comes with a scenario
  step, so the server and the solo engine are held to the same answers.
- **Whole fixtures:** `server/test/start-fixture.test.ts` records a real
  world start. `UPDATE_FIXTURES=1` with `TEST_DATABASE_URL` rewrites it
  after a rule change, and the client test compares the local engine's view
  with it value by value.

## Progress

Tracked in PLAN.md under step 24, now done. Where each part lives in
`client/scripts/local/`:

1. The map: RNG, noise, A*, map generation (`rng.gd`, `noise.gd`,
   `land.gd`, `mapgen.gd`).
2. The store, the routing in `Api` and `Live`, and starting a solo world:
   map, villages, heroes, sites, the first waves (`local_server.gd`,
   `local_host.gd`).
3. Villages: resources, building, training, outposts, upkeep
   (`sim_village.gd`, `sim_resources.gd`).
4. Waves and hordes: setting out (`sched_waves.gd`), arriving, village and
   Holy City battles, the horde AI and camps (`sched_battles.gd`,
   `sim_battle.gd`, `sim_walls.gd`, `sim_horde.gd`, `sched_camps.gd`).
5. The rest: research and rebuilding (`cmd_research.gd`), caravans and the
   vault (`cmd_logistics.gd`), the hero's commands and quests
   (`cmd_heroes.gd`), armies, field battles, forts, roads, bridges, camps
   stormed and sites explored (`cmd_armies.gd`), scouting and settlers
   (`cmd_scouting.gd`), standing orders (`cmd_orders.gd`), the bridge,
   Ritual Night and the end of a run (`cmd_bridge.gd`), and the inbox
   (`inbox.gd`, with the server's notice table bundled as
   `client/data/notices.json`).
6. The start screen's **Play solo**: start, continue and delete solo
   worlds, signed in or not, with or without a connection.

Co-op only: inviting and joining, delegating villages, and push
notifications stay with the server.
