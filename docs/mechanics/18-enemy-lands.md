# 18. The enemy lands

Past the map's edge lie the enemy's own lands. They are being built in
phases (the plan is [`docs/enemy-lands.md`](../enemy-lands.md)). The land,
its rivers and the enemy's settlements are there: armies can march in and
look around. Raids still work as before
([page 13](13-events-and-raids.md#raids-beyond-the-edge)).

## Where they lie

- **Beyond the edge belt.** The enemy lands start on the first ring past the
  map's radius ([page 1](01-world-and-run.md)) and run **10 rings** further
  out.
- **Only behind active fronts.** Each active front owns the wedge on its side
  of the map, the same wedge its edge belt faces. Inactive sides have no enemy
  lands: the ocean stays the map's edge there.
- **Rifts between fronts.** Where two fronts' lands meet, a line of **Rift**
  hexes (impassable) keeps them apart. To go from one front's lands to
  another's, an army comes back through the heartland.
- **Made from the world's seed.** Every world has them, including worlds and
  solo saves started before they existed, and they are the same each time.

## The four bands

Each front's lands are four bands deep, counted outward from the edge:

| Band | Name | Rings |
|---|---|---|
| 1 | The March | 3 |
| 2 | The Forts | 2 |
| 3 | The Heartland | 3 |
| 4 | The Seat | 2 |

Each front's settlements stand in these bands ([below](#settlements)).

## Terrain

Each front paints its lands from its own terrains. None of them can be
settled or built on, and no road runs into them.

| Front | Terrain | Move cost | In battle |
|---|---|---|---|
| North | Dark forest | 3 | Woods |
| North | Frozen Bog | 3 | Wetland |
| North | Barrow Field | 2 | Hills |
| North | Ice | 3 | Open ground |
| East | Steppe | 1 | Open ground |
| East | Salt Flats | 1 | Open ground |
| East | Kurgan Ridges | 2 | Hills |
| South | Olive Groves | 2 | Woods |
| South | Vineyard Terraces | 2 | Hills |
| South | Hallowed Lands | 2 | Open ground |
| West | Mill Meadows | 1 | Open ground |
| West | Abbey Orchards | 2 | Woods |
| West | Hallowed Lands | 2 | Open ground |
| All | Rift | impassable | |

- **The North grows colder inward.** Each band past the first shifts the
  North towards bog, barrows and ice, so its deepest band is mostly ice.
- **Move costs and battle ground** work as on any other terrain
  ([page 2](02-map-and-movement.md#terrain), [page 6](06-battles.md#terrain)).

## Fog and sight

- **The first band is seen** from the start.
- **Deeper bands lie in fog.** The map draws them as grey haze, and they
  can't be picked as a target.
- **An army that reaches a hex** in a band sees the **next band** of that
  front, for the whole world, from then on.
  - Reaching band 1 reveals band 2, band 2 reveals band 3, and so on.
  - Each front's sight is kept apart.

## Marching there

- **Armies can march in** with the *hold* order, like to any hex
  ([page 8](08-armies-and-field.md)). They pay grain as anywhere away from
  home. No supply point or fort can be built there.
- **Hordes keep to the heartland.** They still set out from the edge belt,
  as before ([page 9](09-hordes-and-threats.md)).

## Rivers

- **Two rivers a front.** Each runs along hex edges from the deepest band
  towards the heartland, ending at the band nearest it, a rift or an earlier
  river.
- **Fords.** Every 5th edge of a river can be crossed, as can every bridge the
  enemy builds. Elsewhere a river stops armies as in the heartland
  ([page 2](02-map-and-movement.md#rivers-and-bridges)). Players can't build
  bridges here.

## Settlements

Each active front founds settlements in its lands over the run, the
**deepest band first**, creeping towards the heartland.

- **When.** One per front when the run starts, then one more every **2 game
  days**.
- **Where.** A hex of the band whose turn it is, open land inside the lands
  (not on their outer rim), at least **3 hexes** from any other settlement.
- **Kinds, in order.** The settlements show their front's names:

| Kind | Band | How many | Walls up to | Moat | East | South | West |
|---|---|---|---|---|---|---|---|
| Seat | 4 | 1 | Stone wall | yes | Khan's Ordu | Grand Preceptory | Templar Keep |
| Town | 3 | 3 | Stone wall | yes | Steppe town | Vineyard town | Abbey town |
| Border fort | 2 | 3 | Timber-and-stone wall | yes | Border yurt-fort | Order castle | Commandery |
| War camp | 1 | 4 | Palisade | no | Nomad war camp | Crusader camp | Pilgrim war camp |

- **The North** founds only **monster lairs**: 3 in band 4, 3 in band 3, 2 in
  band 2 and 2 in band 1. Lairs build nothing.
- **Growth.** A settlement starts at **level 1** and grows a level every **24
  game hours**, up to **level 10**. Its walls rise no higher than tier
  1 + (level − 1) / 3, rounded down: a palisade until level 4, timber and
  stone until level 7, stone from level 7. Its level will also set the
  strength of its garrison.
- **Fog.** A settlement shows on the map once its band is seen
  ([above](#fog-and-sight)), with its level on a badge in its front's colour.
  Tap its hex for what it is and builds.

### What they build

Every **6 game hours** each settlement that builds does one work, in this
order:

1. **Palisades** on each of its hex's edges (not across a river).
2. **Its road**, one edge at a time, to the nearest older settlement of its
   front (the seat has none). The road goes round walls, and bridges a river
   in its way first. Where the road meets a settlement's wall, that wall
   becomes a **gatehouse**.
3. **A moat** (seat, towns and border forts): river edges round its ring of
   neighbours, one at a time, already bridged where its road runs.
4. **Raising its walls** a tier at a time, the lowest first, as high as its
   level and kind allow.

The enemy's works stand at once. Its roads speed anyone who uses them, and
its bridges carry anyone across. Its walls stop players' armies like any
wall ([page 7](07-walls-and-sieges.md#walls-along-the-edges)), and **its
gatehouses don't open for them**. On the map the enemy's walls are outlined
in their front's colour.

## Enemy forces

The enemy guards its lands. Its settlements keep garrisons and scouts, and
send out war bands.

- **Garrisons.** A settlement's garrison is its front's troops:
  10 × (1 + 0.3 × (level − 1)) men, times its kind's factor (seat ×2.5,
  town ×1.6, border fort ×1.4, war camp ×1, monster lair ×1.3).
- **Scouts.** A settlement keeps 1 scout, +1 every 3 levels. A sally has 1,
  a patrol 3.

### Being spotted

Every game hour the scouts of each settlement and war band within **3
hexes** of a player's army in their front's lands look for it (an army on a
raid beyond the edge isn't there to see).

- **Each scout** spots the army with a **15%** chance.
- **Your scouts cancel theirs, one for one.** An army with as many scouts as
  the most-scouted watcher near it is never spotted.
- **An army already hunted** isn't looked for again until its hunters are
  done.

### Sallies and patrols

A spotted army draws, and its owner hears of it:

- **A sally:** 60% of the garrison of the nearest settlement within **8
  hexes** that hasn't sallied in the last **12 game hours**.
- **Every patrol** of the front within 8 hexes.

They march at **3 hexes an hour** (the players' walls stop them, their own
don't) to where the army was spotted.

- **Caught.** If the army is within 1 hex when they arrive, they fight it
  where it stands: a battle like a raid's ([page 13](13-events-and-raids.md#raids-beyond-the-edge)),
  the army against the band. The army stays on its hex (or falls); what's
  left of the band goes home.
- **Chase.** An army that moved off is followed up to **3 hexes** further,
  while it is still in the enemy lands. Otherwise the band goes home.
- **Patrols.** Each front keeps up to **2 patrols** marching between its
  settlements, 35% of a garrison each. One more sets out every **8 game
  hours** once a front has two settlements.
- **On the map,** war bands show as pennants in their front's colour with
  their strength, a hunting band's road dotted red. Those deeper than the
  bands you've seen aren't shown, unless they hunt your army.

