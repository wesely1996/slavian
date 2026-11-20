# 12. Scouting, exploration and expansion

[← Research, faith and the Blacksmith](11-research-faith-smithing.md) · [Index](README.md) · Next: [Events and raids beyond the edge →](13-events-and-raids.md)

## Scouts

The Scout Lodge trains three kinds of scout:

| Scout | Lodge | Speed | Stealth | Intel | Special |
|---|---|---|---|---|---|
| Scout | 1 | 12 | 1.0 | 1 | |
| Pathfinder | 3 | 16 | 0.5 | 2 | Eases harsh terrain for an army |
| Assassin | 6 | 14 | 0.35 | 3 | 10% each to kill a horde's leader |

- **Sending them.** Scouts of every kind can go together, at the pace of the
  slowest. A mission takes up to 20.
- **Never fighting.** Scouts are support units: they stand aside in battle and aren't struck.

## Scouting a horde

The wave schedule is public. **What a horde is made of** is learned by
sending scouts at it.

### Coming back alive

Each scout that reaches the horde survives with a chance set by the front,
scaled by its stealth:

```
caught   = (1 − front's survival) × stealth
survives = 1 − caught + scoutSurvival bonuses
```

| Front | Base survival |
|---|---|
| North | 75% |
| East | 65% |
| South | 80% |
| West | 80% |

- **Stealth.** A plain scout has the base chance. An assassin, with stealth
  0.35, is caught a third as often.
- **Bonuses** (in points): Sokol +30, Gavran +25, Woodcraft and Night Runners
  +10 each, Firebird Couriers +15, hero skills and traits, the Shrine of
  Stribog.

### The report

The surviving scouts' **intel** decides the report:

| Report | Intel needed | Size shown | Units shown | Stance |
|---|---|---|---|---|
| Rough | 1 | ±30% | — | hidden |
| Detailed | 3 | ±10% | each ±25% | shown |
| Exact | 6 | exact | exact | shown |

Example: two surviving pathfinders (intel 2 each) give a detailed report.
The hero's "Ride beyond the border" quest gives a full report too
([page 10](10-heroes-generals-clans.md#quests)).

### Assassins

- **The kill.** Each surviving assassin has a 10% chance to **kill the horde's
  leader**.
- **The result.** Its skills and grudge are gone from that horde, and a rival
  rises at a third of its level ([page 9](09-hordes-and-threats.md#enemy-leaders)).

## Scouts with an army

- **Intel bonus.** Scouts sent with an army give it **intel**: +2% attack and
  defense per point, at most +10% (5 plain scouts, or 2 assassins).
- **Pathfinders** also ease the march ([page 2](02-map-and-movement.md#how-travel-time-is-worked-out)).

## Searching for ruins

Scouts can search for **forgotten ruins**:

- **Who goes.** 2 to 6 scouts leave the village for **3 game hours**.
- **What they find.** When they come back, they have found a new ancient site
  with a **15% chance per scout**, at most 90%. The site lies within 5 hexes
  of the village, on free ground that suits a kind of site, at least 3 hexes
  from other sites.
- **How often.** A player sends one search at most every **12 game hours**,
  over all their villages.

## Ancient sites

### Where they are

- **How many.** At least 5 per world, 3 per player, placed when the world
  starts.
- **Where.** Most lie in the **borderlands** (within 2 rings of the edge, the
  edge belt included). 30% lie mid-map, 30–60% of the way out from the Holy
  City.
- **Spacing.** Sites are at least 3 hexes apart, and 3 from the starts.

| Site | Terrain | Search | Guarded | Finds (weights: resources / gear / scroll) | Ember |
|---|---|---|---|---|---|
| Kurgan | Plains, hills, wooded hills, steppe | 4 h | 30% | 4 / 3 / 2 | 20% |
| Sunken Shrine | Swamp, forest | 6 h | 40% | 2 / 2 / 4 | 20% |
| Old Hillfort | Hills, wooded hills, plains, hallowed | 5 h | 60% | 3 / 4 / 1 | 20% |
| Stone Idol | Plains, forest, steppe | 3 h | 20% | 2 / 1 / 3 | 15% |
| Frozen Ruin | Ice, dark forest | 8 h | 70% | 2 / 3 / 2 | 30% |

### Guardians

A guarded site is watched by a band of the North's beasts:

- **Size.** 10 units, more the further out (up to ×2.5 at the edge), drawn as
  a horde of wave 5.
- **Seeing them.** They are unknown until someone sees them.
- **Fighting them.** An army sent to explore fights them first.

### Searching a site

An army with orders *explore* searches the site (after any guardians):

- **Time.** The site's hours, divided by 1 + 5% for every unit beyond the
  first, never under a quarter.
- **Without scouts** it takes **3×** as long.
- **One find.** The army comes home with one find, picked by the site's
  weights:
  - **Resources:** 400 wood, 400 stone, 300 grain, 250 iron, ×(1 + how far
    out it lies), Zmija +25%.
  - **A piece of hero gear.**
  - **A lore scroll** the group hasn't found yet (otherwise resources).
- **Scouts' bonus.** Scouts along bring **extra resources**: +10% of the loot
  per scout, at most +50%.
- **An Ember.** On top of the find, a chance of a Svarog's Ember: the site's
  chance divided by the number of players.

An army holding a hex with an unsearched site searches it on arrival. The
hero's "Search the ruins" quest searches an unguarded site in person.

## Outposts

- **Claiming.** An outpost is claimed on a resource hex within 2 hexes of a
  village. A village holds 1, plus 1 for every 2 Elder's Hall levels.
- **Yields and risks:** see [page 4](04-economy-and-logistics.md#outposts).
- **Abandoning.** An outpost can be abandoned.
- **A blocked hex.** No village can be founded on a hex with an outpost.

## Founding villages

There is **no cap** on villages. Expansion is limited by the settlers' rising
price, each village's grain upkeep and the land itself.

1. **Settlers.** Train **3 settlers** at a Settlers' Lodge
   ([page 5](05-units-and-training.md#settlers)).
2. **The site.** Pick any settleable hex (plains, forest, hills, wooded hills)
   anywhere inside the play area:
   - at least **3 hexes** from every village,
   - at least **2 hexes** from the Holy City,
   - with no outpost on it.
3. **The walk.** The settlers walk there at their speed (4, or faster with a
   forged harness) and found the village.

The new village:
- **Starts with** 300 wood, 300 stone, 300 grain and 150 iron.
- **Takes its 12 fields** from the land within 2 hexes: one of each kind, the
  rest by what that land yields.
- **Costs upkeep:** the n-th village founded costs (n − 1) × 3 grain an hour.

### Village sites

The land under and around a village decides its terrain buildings
([page 3](03-villages-and-buildings.md#terrain-buildings)):

| Land | Buildings |
|---|---|
| Beside a lake, or a river on one of its edges | Fisherman's Hut, Water Wheel |
| On hills | Windmill |
| On plains | Ranch |
| Next to a mountain | Mountain Lodge |
