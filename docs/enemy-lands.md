# Enemy lands: a plan for the map beyond the edge

A plan, not settled design: nothing here is built yet. When parts of it are
agreed they move into `PLAN.md` and, once they play, into `docs/mechanics/`.

## 1. Why

Today the enemy has no ground of its own. The hordes appear on the edge belt
and march in. A raid "beyond the map's edge" is a timer and three dice rolls
(`data/raids.json`): the army stands on the last ring while its battles are
fought somewhere no one can see. That leaves gaps:

- **The other side is a menu, not a place.** The Monster Lair or the Templar
  Keep is a name in the Raid tab. Players can't see it, scout it, cut its
  roads or watch it rebuild.
- **Hordes come from nowhere.** A gathering horde is a countdown. Striking it
  is one battle with no march, no ground and no choice of where to hit.
- **Late game flattens.** Once a group holds its ring, the only push outward is
  the raid timer. Hatred, depth and loot (0.23) give it numbers, but not a
  map.

The expansion adds **enemy lands**: a belt of real hexes beyond the edge on
every active front, with the enemy's own camps, towns, roads and muster
grounds. Armies march into them; what happens there changes the hordes that
come out.

## 2. What stays the same

- **The heartland.** The Holy City, the starting ring, rivers, the edge belt,
  fog of war and the bridge endgame stay as they are.
- **Inactive fronts.** These keep their ocean or plain land: no enemy lands
  there.
- **Rules carry over.** Battles, sieges, stances, maneuvers, supply, hatred
  and the horde AI are reused. The new places are built from existing pieces
  (camps, forts, raid stages).
- **Mobile first.** Everything stays one tap away on a phone held upright.

## 3. The shape of the map

```
      Holy City (0,0)
          │  heartland: radius R (10–16 by players)
          │  edge belt: 1–2 rings (dark forest, steppe, hallowed lands)
          ▼
   ┌───────────────── enemy lands: 6–8 more rings ─────────────────┐
   │ band 1 (march)   band 2 (heartland)   band 3 (the seat)        │
   │ camps, patrols   towns, roads         the front's capital      │
   └────────────────────────────────────────────────────────────────┘
```

- **Sectors.** Each active front owns the wedge of the outer rings on its side
  (the same sides `mapgen` paints the edge belt on). Wedges meet at
  impassable seams (ice fields, salt marsh, mountain walls), so fronts don't
  bleed into one another.
- **Bands.** The enemy lands are three bands deep, matching today's raid
  depth:
  - **Band 1, the march:** camps and patrols, light garrisons.
  - **Band 2, the heartland:** towns joined by roads, muster grounds.
  - **Band 3, the seat:** one capital (the stronghold of today's raids) and
    its shrine or forge.
- **Size.** About +60–80% more hexes than today (radius R + 8 rather than
  R + 1). The map client and the server's hex tables must cope (§9).
- **Terrain per front.** Each front gets its own palette: new terrains with
  their own move costs and battle ground (`data/terrain.json`):
  - **North:** dark forest, ice, frozen bog, barrow fields.
  - **East:** steppe, kurgan ridges, salt flats, river fords.
  - **South:** vineyard terraces, olive groves, pilgrim roads.
  - **West:** mill meadows, abbey orchards, stone bridges.

  These are today's raid fields (`raids.json` fronts), made into terrain.

## 4. What stands there

| Place | Band | Role | Reuses |
|---|---|---|---|
| **War camp** | 1 | A garrison and a little loot; scouts' first sight of the front | bandit camp / lair |
| **Watch post** | 1 | Sees our armies coming: hordes and towns are warned | watchtower rule |
| **Town** | 2 | Stores, a garrison that regrows, walls; feeds the front's waves | fort (rings, towers, siege) |
| **Muster ground** | 2 | Where the next horde gathers, visibly, unit by unit | gathering horde, strike |
| **Road** | 1–3 | Hordes and enemy reinforcements move along them faster | our roads |
| **Shrine / forge** | 3 | The front's rare finds (Embers, gear, lore) | North raid finds |
| **Capital** | 3 | The stronghold; sacking it is the deepest blow | raid stronghold |

- **Enemy settlements** are a new entity, `enemy_settlements`: front, kind,
  hex, tier, garrison, stores, walls, status (`standing`, `besieged`,
  `sacked`, `rebuilding`) and when it regrows.
- **Garrisons** are built like a wave of the front (`composeWave`), scaled by
  band, the waves so far and the front's hatred: the same growth the raid
  stages use today.

## 5. Playing there

- **Getting there.** Armies, scouts and expeditions can target any hex in the
  enemy lands. Enemy terrain and zone of control (around towns, like our forts)
  slow them.
- **Supply.**
  - There is no friendly granary beyond the edge: an army lives on what it
    carries.
  - Supply points can't be set up there, but a captured war camp can serve as
    one while it is held.
  - Foraging enemy stores is the other way to eat, and it raises hatred.
- **Scouting.** Enemy lands start in fog.
  - Scouts reveal them band by band, and watch posts may catch them.
  - A scouted town shows its garrison and walls, as a horde report does.
- **Battles.**
  - Field battles use the hex's own terrain, so no field is rolled any more.
  - Camps are fought like camps. Towns and the capital are besieged ring by
    ring, like our forts (PR B), with the front's engines defending.
- **Sacking.** Taking a place brings its stores (the 0.23 loot rules: richer
  by band and by hatred) and a mark on the front:
  - **A war camp:** loot, and sight of band 2.
  - **A town:** loot, and the front's waves are **10% smaller** while it lies
    in ruins (stacking, at most −30%).
  - **A muster ground:** the gathering horde loses what stood there, as a
    strike does today, but on the map.
  - **The capital:** the front's next wave is skipped, and its waves are
    20% smaller for N days; an achievement.
- **Regrowth.**
  - Sacked places rebuild after some game days, faster the more the front
    hates.
  - Hatred rises with every blow, so pressure comes back as **retaliation
    bands** aimed at the village that struck. This is today's 100%-hatred
    band, made specific.
- **Holding ground.**
  - Optional, phase 5: a captured war camp can be turned into a fort or a
    supply point.
  - **No villages** in enemy lands: they stay unsettleable, so the economy
    stays at home.

## 6. The hordes, made visible

- **Muster.** A wave no longer appears on the edge. It gathers at a muster
  ground over its countdown, visibly (the gathering share that `strike` uses
  today), then marches out along the front's roads.
- **Why it matters.**
  - Players can see where the next horde will come from, cut its road (a fort
    on it), or hit it while it gathers.
  - Towns sacked along its road slow it or shrink it.
- **Wave strength** gains one more input: the front's standing towns (those
  not sacked). Group power, difficulty and bridge stages still apply.
- **Events reuse the ground.**
  - The Avatar's cultists, the Leshen and mountain cities keep their own
    rules.
  - A front's capital becomes the natural stage for its endgame host on
    Ritual Night.

## 7. What changes for today's systems

| System | Change |
|---|---|
| Raids (`raids.json`) | Become ordinary army orders on real places. Depth = band. The Raid tab becomes a "Campaign" tab listing known enemy places by band |
| Strike | Becomes an attack on a muster ground: same share-gathered rule, now with a march |
| Hatred | Unchanged in kind. Sacks, foraging and capital strikes add to it; regrowth speed reads it |
| Waves | Spawn at muster grounds; size reads standing towns |
| Map gen (`mapgen`) | Generates the outer bands, seams, enemy terrain and places, all seeded |
| Fog | Enemy lands start hidden; scouting reveals them band by band |
| Achievements | New ones for sacking each kind of place and each capital |
| Bridge quests | The "artifact" quest (raid the North to full depth) becomes "sack the Monster Lair" |

## 8. Running worlds

- **Lazy creation.** Worlds started before the expansion get their enemy
  lands generated the first time the server starts with it.
  - It uses the world's seed, so the result is the same each time.
  - The outer rings go beyond today's radius, so nothing players built
    moves.
- **Raids under way** finish under the old rules. New ones use the map.
- **The solo engine** does the same on loading an older save.

## 9. Technical notes

- **Hex count.**
  - A radius-16 map grows from ~800 hexes to ~1,700.
  - The client draws terrain in chunks and skips off-screen chunks.
  - The world view keeps sending the map once. Enemy places travel with the
    world view like camps do.
- **Path search.**
  - `fastestStep` and the land cache grow with the map.
  - Pathing for hordes and armies already caps its search. The caps need
    revisiting.
- **Data.** A new `data/enemy-lands.json` holds:
  - band widths and seams;
  - place kinds per band, with garrisons, stores, walls and regrowth hours;
  - per-front terrain palettes;
  - wave-size effects of sacked towns and the capital.
- **Parity.** Every new route and scheduler event comes with a scenario step
  and a GD mirror (`client/scripts/local/`). `parity.test.ts` keeps them
  honest.
- **State machines.** Enemy settlements get their own section in
  `docs/state-machines.md` (`standing → besieged → sacked → rebuilding →
  standing`).

## 10. Phases

Each phase is one or two PRs, playable on its own, behind no flag.

1. **The land itself.**
   - Generate the outer bands and seams with per-front terrain; draw them
     with chunked rendering; fog.
   - Nothing lives there yet, but armies and scouts can walk in.
2. **Places.** War camps, watch posts, towns and the capital, with
   garrisons; scouting reports on them; sieges reuse fort rules; sacking with
   loot.
3. **Muster grounds.** Waves gather and set out from them; strike becomes a
   march; towns standing feed wave size.
4. **Consequences.** Wave reductions for sacked towns and capitals; regrowth;
   retaliation bands; the Campaign tab replaces the Raid tab; achievements.
5. **Holding ground** (optional): captured camps as supply points or forts;
   roads into enemy lands.
6. **Balance pass.** `runsim` gets bots that campaign. Hatred, regrowth and
   wave reductions are tuned so that pushing out pays, but sitting at home
   still works on Baron difficulty.

## 11. Open questions

- **How deep?** Three bands of 2–3 rings, or one wide band with places
  scattered by distance?
- **Holding ground:** may players keep anything beyond the edge (camps as
  forts), or only strike and leave?
- **Retaliation:** one band at the village that struck (sharp, readable), or
  a share of the front's next wave (softer)?
- **Inactive fronts:** stay empty, or become neutral wilds with lairs and
  ruins for small groups?
- **Raids:** keep the old abstract raid as a quick option next to real
  campaigns, or replace it outright?
