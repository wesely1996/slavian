# 18. The enemy lands

Past the map's edge lie the enemy's own lands. They are being built in
phases (the plan is [`docs/enemy-lands.md`](../enemy-lands.md)). For now
the land itself is there: armies can march in and look around. Raids still
work as before ([page 13](13-events-and-raids.md#raids-beyond-the-edge)).

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

The bands are empty for now. Camps, border forts, towns and each front's
seat come in a later phase.

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
