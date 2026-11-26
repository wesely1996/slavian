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
   ┌─────────────────────── enemy lands: 8–10 more rings ───────────────────────┐
   │ band 1 (march)   band 2 (forts)    band 3 (heartland)   band 4 (the seat) │
   │ camps, patrols   the front's       towns, muster        the front's       │
   │                  border forts      grounds, roads       capital           │
   └────────────────────────────────────────────────────────────────────────────┘
```

- **Sectors.** Each active front owns the wedge of the outer rings on its side
  (the same sides `mapgen` paints the edge belt on). Wedges meet at
  impassable seams (ice fields, salt marsh, mountain walls), so fronts don't
  bleed into one another.
- **Bands.** The enemy lands are four bands deep:
  - **Band 1, the march:** camps and patrols, light garrisons.
  - **Band 2, the forts:** a line of the front's border forts, walled and
    garrisoned, guarding the ways in. An army must take one (or slip past
    its zone of control) to go deeper.
  - **Band 3, the heartland:** towns joined by roads, muster grounds.
  - **Band 4, the seat:** one capital (the stronghold of today's raids) and
    its shrine or forge. The hardest place in the game to take.
- **The North is different: monster lands.** It has no forts, towns or
  capital, only **monster lairs**, in every band. The further north, the
  **more lairs** and the **more and stronger monsters** in each: band 1
  holds wolf dens, band 4 the deepest lairs of the Div and the Zmey. Its
  seat is the Monster Lair of today's raids, the greatest lair of all. What
  §4–§6 say of camps, forts and towns, the North does with lairs.
- **Size.** About +80–100% more hexes than today (radius R + 10 rather than
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
| **Border fort** | 2 | Walls, towers and a strong garrison across the way in; a zone of control | fort (rings, towers, siege) |
| **Town** | 3 | Stores, a garrison that regrows, walls; feeds the front's waves | fort (rings, towers, siege) |
| **Muster ground** | 3 | Where the next horde gathers, visibly, unit by unit | gathering horde, strike |
| **Road** | 1–4 | Hordes and enemy reinforcements move along them faster | our roads |
| **Shrine / forge** | 4 | The front's rare finds (Embers, gear, lore) | North raid finds |
| **Capital** | 4 | The stronghold; sacking it is the deepest blow | raid stronghold |
| **Monster lair** (North) | 1–4 | Every place in the North: more and stronger the deeper | lair |

- **Enemy settlements** are a new entity, `enemy_settlements`: front, kind,
  hex, tier, garrison, stores, walls, status (`standing`, `besieged`,
  `sacked`, `rebuilding`) and when it regrows.
- **Power.** Garrisons are built like a wave of the front (`composeWave`),
  scaled the way hordes and camps already are (PR5 power scaling):
  - by **the group's power** (army and economy), so a place is a fight
    whatever stage the run is at;
  - by **difficulty** (`difficulty.json` presets), so Baron stays forgiving
    and the hardest presets punish;
  - by **band** (each band clearly harder than the last; the seat far
    beyond: about what a full Ritual Night host is);
  - by the front's **hatred** and its **gods' blessings** (§6b).

## 5. Playing there

- **Getting there.** Armies, scouts and expeditions can target any hex in the
  enemy lands. Enemy terrain and zone of control (around towns, like our forts)
  slow them.
- **Supply.**
  - There is no friendly granary beyond the edge: an army lives on what it
    carries.
  - Supply points can't be set up there, and captured places can't be held.
  - Foraging enemy stores is the other way to eat, and it raises hatred.
- **Scouting.** Enemy lands start in fog.
  - Scouts reveal them band by band, and watch posts may catch them.
  - A scouted town shows its garrison and walls, as a horde report does.
- **Battles.**
  - Field battles use the hex's own terrain, so no field is rolled any more.
  - Camps are fought like camps. Towns and the capital are besieged ring by
    ring, like our forts (PR B), with the front's engines defending.
- **Sacking.** Taking a place brings its stores and a mark on the front:
  - **A war camp:** loot, and sight of band 2.
  - **A border fort:** loot, and the way into band 3 open while it is down.
  - **A town:** loot, and the front's waves are **10% smaller** while it lies
    in ruins (stacking, at most −30%).
  - **A muster ground:** the gathering horde loses what stood there, as a
    strike does today, but on the map.
  - **The seat:** **no horde of that front sets out for 1 game day**: its
    raids stop. It should be **very, very hard** (the strongest host in the
    game behind the strongest walls, after crossing three bands) and **very,
    very rewarding**: the greatest loot of the run, Embers, rare gear and
    lore, an achievement.
- **Rewards fit the risk.** What a sack brings is scaled to:
  - **the place's power** (band, group power, difficulty, hatred): the
    harder it was, the more it gives;
  - **what the expedition spent**: the troops lost and the grain eaten on
    the way. A costly victory pays for itself and more; a cheap raid on a
    weak camp pays little. Loot keeps the 0.23 depth and hatred factors.
- **Repair.** A sacked camp, fort, town or lair **rebuilds after 12 game
  hours** (the seat too), at full strength.
- **Retaliation.** Hatred rises with every blow, so pressure comes back as
  **retaliation bands** aimed at the village that struck. This is today's
  100%-hatred band, made specific.
- **No holding ground.** Nothing beyond the edge can be kept: no villages,
  no supply points, no captured camps turned into forts. An army that
  lingers there after its fight (more than 2 game hours on enemy ground
  without striking a place) draws the front's **guardian**: a god's wrath or
  a huge monster that **drives the army home** (it is teleported back to its
  village, losing a share of its men if it stands to fight). Expeditions
  strike and leave.
- **Hatred hardens the land.** A front's hatred raises the garrisons **and
  the walls** of its camps, forts, towns, lairs and seat, as it raises its
  hordes.
- **Striking the seat** adds a **lasting +3% hatred** to that front, win or
  lose: the attack alone is remembered.

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
- **Several at once.** A front may have several hordes out at the same time
  (as the bridge-stage hordes already are): its muster grounds each gather
  their own.

## 6b. The enemy's gods

The enemy has gods too, and they answer as ours do (§ "Blessings of the
gods" on page 13 of the mechanics docs).

- **Earned by the enemy's anger and our deeds:**
  - **hatred:** each time a front's hatred passes a threshold (e.g. 200%,
    400%);
  - **the bridge:** each stage the group raises draws a blessing for every
    active front (Nav fights the bridge);
  - **events:** a burned forest's Leshen felled, the Avatar of Černobog
    risen, a seat sacked, a river god's or forge god's blessing won by the
    players.
- **What a blessing gives:** a lasting bonus for that front, such as:
  - stronger garrisons in a band;
  - faster repair of sacked places;
  - a new unit in its hordes;
  - walls of its forts and towns made tougher.

  Each front has its own gods and blessings: the Order's saints, the
  nomads' sky-father, the North's Černobog and the old things under the
  ice.
- **Shown to the players:** each front's blessings sit on its panel, so the
  cost of provoking it is visible.
- **Events reuse the ground.**
  - The Avatar's cultists, the Leshen and mountain cities keep their own
    rules.
  - A front's capital becomes the natural stage for its endgame host on
    Ritual Night.

## 7. What changes for today's systems

| System | Change |
|---|---|
| Raids (`raids.json`) | **Replaced** by planned campaigns: before setting out, the player picks the target place (its band is the depth), the route through the bands and the places struck on the way. The Raid tab becomes a "Campaign" tab listing known enemy places by band, with the planner |
| Strike | Becomes an attack on a muster ground: same share-gathered rule, now with a march |
| Hatred | Unchanged in kind. Sacks, foraging and capital strikes add to it; regrowth speed reads it |
| Waves | Spawn at muster grounds; size reads standing towns |
| Map gen (`mapgen`) | Generates the outer bands, seams, enemy terrain and places, all seeded |
| Fog | Enemy lands start hidden; scouting reveals them band by band |
| Achievements | New ones for sacking each kind of place and each capital |
| Bridge quests | The "artifact" quest (raid the North to full depth) becomes "sack the Monster Lair". Every raised stage also blesses the enemy (§6b) |

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
  - A radius-16 map grows from ~800 hexes to ~2,000.
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

1. **The land itself** (done).
   - Generate the outer bands and seams with per-front terrain; draw them
     with chunked rendering; fog.
   - Nothing lives there yet, but armies and scouts can walk in.
2. **Places.**
   - War camps, watch posts, border forts, towns and the capital; the
     North's lairs in every band.
   - Garrisons scaled by group power, difficulty and band.
   - Scouting reports; sieges reuse fort rules; sacking with risk-scaled
     loot; 12-hour repair.
3. **Muster grounds.** Waves gather and set out from them; strike becomes a
   march; towns standing feed wave size.
4. **Consequences.**
   - Wave reductions for sacked towns; the seat's day without raids.
   - Retaliation bands at the village that struck; achievements.
   - Planned campaigns (target, depth, route) replace the old raid; the
     Campaign tab replaces the Raid tab.
   - The guardian that drives lingering armies home; +3% lasting hatred
     for striking the seat.
5. **The enemy's gods** (§6b): blessings from hatred, bridge stages and
   events, shown on each front's panel.
6. **Balance pass.** `runsim` gets bots that campaign. Hatred, regrowth and
   wave reductions are tuned so that pushing out pays, but sitting at home
   still works on Baron difficulty.

## 11. Settled

- **Four bands** (march, forts, heartland, seat); the North all monster
  lairs, more and stronger to the north.
- **The seat:** sacking it stops that front's hordes for 1 game day; very,
  very hard and very, very rewarding.
- **Repair:** any sacked place rebuilds in 12 game hours.
- **Scaling:** place power by group power and difficulty; rewards by the
  risk and by what the expedition spent.
- **Several hordes per front** may be out at once.
- **The enemy's gods** bless their fronts, from hatred, the bridge and
  events.
- **No holding ground:** a guardian (a god or a huge monster) drives armies
  that linger beyond the edge back home.
- **Retaliation:** one band aimed at the village that struck.
- **Raids:** the old abstract raid is replaced by planned campaigns (target,
  depth and route chosen before setting out).
- **Hatred** also raises the defences of enemy places, not only hordes.
- **The seat:** attacking it adds a lasting +3% hatred, whatever the result.
- **Inactive fronts** stay empty: no enemy lands beyond them (the edge belt
  stays the map's edge there).

## 12. Open questions

None left; tuning numbers are for the balance pass.
