# 3. Villages and buildings

[← Map, movement and terrain](02-map-and-movement.md) · [Index](README.md) · Next: [Economy and logistics →](04-economy-and-logistics.md)

## The village

A village takes one hex. Its interior has two kinds of plots:

- **12 fields** around it, each with one resource building (woodcutter,
  quarry, farm, iron mine), each upgraded on its own.
  - **A starting village** (or a refugee camp) has a balanced set: 3
    woodcutters, 3 quarries, 4 farms, 2 iron mines.
  - **A village founded by settlers** takes its fields from the land within 2
    hexes. It gets one of each kind, and the rest are shared out by what that
    land gives.
- **12 centre slots** for buildings, the first holding the **Elder's Hall**.
  - 4 slots are open at the start, and every Hall level above 1 opens one
    more (all 12 at Hall level 9).
  - **The walls** have their own plot, and the **wall slots** for towers open
    with the walls ([page 7](07-walls-and-sieges.md)).

**A new village** starts with 500 wood, 500 stone, 500 grain and 300 iron. A
village founded by settlers starts with 300 / 300 / 300 / 150.

## The Elder's Hall

The heart of the village, up to level 10. Each level:

- **Opens** one more centre slot.
- **Builds faster.** Construction time × 0.96 for every level above 1. At
  Hall level 10 everything builds in 0.96⁹ ≈ 69% of the time.
- **Every 3 levels** adds a place in the build queue (5 at the start) and a
  standing order slot ([page 4](04-economy-and-logistics.md#standing-orders)).
- **Every 2 levels** allows one more outpost (1 at the start).
- **Army slots.** Adds 20 army slots, on top of the village's 30
  ([page 5](05-units-and-training.md#army-slots)).

### Ten levels again

The regular buildings, fields and towers went up to level 20 for a while,
and in 0.23 each of ten levels stood for two of the old ones. Since
0.24 the ten levels give and take what the first ten did before the twenty:
the same production, storage, build times, unlock levels and per-level
effects. A level costs what it did then, plus 20% (since 0.23.1). Villages
saved on twenty levels were halved, rounded up (old level 7 became 4), and
keep their levels; their production and stores are counted again from the
levels they hold. The buildings added while there were twenty levels
(Masons' Guild, Workers' Huts, Blacksmith) keep what they reach at level 10.
The land's and the specialists' own buildings (Academy, Shrine, boosters,
terrain buildings) keep their 5 levels.

## Cost and time of a level

For a building with base cost *C*, cost growth *g*, base time *T* and time
growth *t*:

```
cost of level n = C × g^(n−1)
time of level n = T × t^(n−1) × 0.96^(Hall level − 1) × (1 + buildTime bonus) / world speed
```

Negative `buildTime` bonuses speed building up:
- **Research:** Master Builders −10%, Svarog's Living Flame −15%.
- **Clan:** Jelen −10%.
- **Hero:** Mikula −10%.
- **The Shrine** of Svarog: −3% a level.
- **Buildings:** the Masons' Guild −4% a level, the Water Wheel −3% a level.
- **The bridge:** the second stage's blessing, −20%.

## Building list

Costs are wood / stone / grain / iron at level 1, then ×growth each level.

### The core

| Building | Max | Level 1 cost | Growth | Time | What it does |
|---|---|---|---|---|---|
| Elder's Hall | 10 | 240/240/120/96 | ×1.6 | 180 s ×1.5 | Slots, build speed, queue, outposts, army slots (above) |
| Woodcutter (field) | 10 | 48/72/36/24 | ×1.6 | 90 s ×1.55 | 15 wood/h at level 1, ×1.35 a level |
| Quarry (field) | 10 | 84/36/36/24 | ×1.6 | 90 s ×1.55 | 12 stone/h, ×1.35 a level |
| Farm (field) | 10 | 60/48/24/12 | ×1.6 | 75 s ×1.55 | 15 grain/h, ×1.35 a level |
| Iron Mine (field) | 10 | 96/96/48/0 | ×1.65 | 120 s ×1.6 | 8 iron/h, ×1.35 a level |
| Storehouse | 10 | 144/120/48/24 | ×1.5 | 100 s ×1.5 | Storage for every resource (several allowed) |
| Grain Silo | 10 | 168/144/24/24 | ×1.5 | 110 s ×1.5 | Storage for grain alone (several allowed) |

### Military

| Building | Max | Level 1 cost | Growth | What it does |
|---|---|---|---|---|
| Barracks | 10 | 180/144/72/72 | ×1.6 | Trains infantry; faster each level; higher levels open stronger troops |
| Shooting Range | 10 | 204/108/72/60 | ×1.6 | Trains archers, skirmishers, throwers and engines |
| Stables | 10 | 192/120/144/84 | ×1.6 | Trains riders and military caravans |
| Scout Lodge | 10 | 120/96/48/24 | ×1.6 | Trains scouts, pathfinders, assassins |
| Hospital | 10 | 216/192/144/48 | ×1.6 | 5% a level of a garrison's fallen get up again when it holds its village; trains the Shaman |
| Hero's Hall | 10 | 216/192/120/96 | ×1.6 | Recruits generals; heals the hero 8% faster a level there |
| Blacksmith | 10 | 240/216/72/264 | ×1.6 | Forges unit improvements, 6% faster a level ([page 11](11-research-faith-smithing.md#the-blacksmith)) |
| Walls and towers | 10 | see [page 7](07-walls-and-sieges.md) | | |

### Economy and growth

| Building | Max | Level 1 cost | Growth | What it does |
|---|---|---|---|---|
| Caravan Yard | 10 | 144/120/72/48 | ×1.55 | One caravan per level; merchants ([page 4](04-economy-and-logistics.md#caravans)) |
| Market | 10 | 192/144/120/48 | ×1.6 | Trades resources; bounty board; buys spare gear |
| Academy | 5 | 250/300/150/150 | ×1.7 | Research 30/h at level 1, ×1.35 a level ([page 11](11-research-faith-smithing.md)) |
| Settlers' Lodge | 5 | 300/250/200/100 | ×1.6 | Trains settlers |
| Shrine | 5 | 60/100/500/20 + 1 Ember a level | ×1.45 | A god's blessing for all your villages; needs Elder's Hall 3 |
| Masons' Guild | 10 | 240/288/96/72 | ×1.6 | Every building 4% faster a level |
| Workers' Huts | 10 | 264/192/168/48 | ×1.6 | +4% of every resource a level |
| Forester | 5 | 160/120/60/40 | ×1.7 | +5% wood a level; needs a Woodcutter of level 5 |
| Stonemason | 5 | 120/160/60/40 | ×1.7 | +5% stone a level; needs a Quarry of level 5 |
| Mill | 5 | 140/120/60/40 | ×1.7 | +5% grain a level; needs a Farm of level 5 |
| Smelter | 5 | 160/140/60/60 | ×1.7 | +5% iron a level; needs an Iron Mine of level 5 |

Forester, Stonemason, Mill and Smelter may stand in more than one slot, and
their effects add up.

### Terrain buildings

These can only be built where the land allows:

| Building | Where | Max | What it does |
|---|---|---|---|
| Fisherman's Hut | Beside a lake or on a river | 10 | 10 grain/h, ×1.3 a level |
| Water Wheel | Beside a lake or on a river | 5 | +3% every resource and 3% faster building a level |
| Windmill | Village on hills | 5 | +6% grain a level |
| Ranch | Village on plains | 5 | 12 grain/h, ×1.35 a level; cavalry +2% attack and defense a level |
| Mountain Lodge | Next to a mountain | 5 | +5% wood, stone and iron a level |

### Clan buildings

Only that clan's members can build these ([page 10](10-heroes-generals-clans.md#clans)):

| Building | Clan | What it does, per level |
|---|---|---|
| Granary-Temple | Jelen (Stag) | 12 grain/h (×1.3 a level), troops eat 2% less |
| Stone Redoubt | Medvěd (Bear) | +4% defense at home |
| Longhouse Hall | Volk (Wolf) | Troops eat 3% less, train 2% faster |

## The build queue

- **Size.** A village queues up to 5 builds, plus one every 3 Elder's Hall
  levels.
- **One at a time.** Builds run in queue order. A queued build is paid when it
  is queued.
- **Cancelling** a queued build returns 80% of its cost, plus 2% for every
  Elder's Hall level above 1, at most all of it.
  - Later levels of the same plot are cancelled with it, and the builds after
    it move up.
  - Embers paid for a Shrine level come back in full.

## Demolishing and abandoning

- **Demolishing** a building returns **50%** of everything it cost, over all
  its levels.
- **Abandoning** a whole village sends 50% of everything that stood there to
  the Holy City vault.

## Ruins and rebuilding

A horde that **razes** a village leaves a **ruin** ([page 9](09-hordes-and-threats.md#raid-or-raze)).

- **Stores** in the village are lost.
- **Rebuilding** costs **40%** of everything that stood there and takes 6 game
  hours, after which the village returns as it was.
- **Room for it.** Until it is rebuilt, a ruin's stores hold at least what
  rebuilding it costs, however small its storehouse is now.
- **Sending help.** Caravans can carry resources to a ruin, yours or a
  teammate's ([page 4](04-economy-and-logistics.md#caravans)); merchants
  don't trade there.
- **What a ruin can still do.** It can't build or train. Armies, forts,
  roads, bridges and terraforming can still be sent from it.
- **The refugee camp.** A player left with nothing but ruins gets one on the
  nearest free settleable hex at least 2 hexes from the Holy City. Hordes
  raid refugee camps but never raze them.

## The garrison

- **Who is in it.** Troops at home and in training.
- **Eating.** They eat a quarter of their grain upkeep.
- **Fighting.** They fight the village's battles in the village's stance.
- **Leaving.** They leave only by joining an army ([page 8](08-armies-and-field.md)).
- **Dismissing.** Soldiers can be dismissed.

The **recommended garrison** is 10 units, plus 5 for every village after
the first.
