# 4. Economy and logistics

[← Villages and buildings](03-villages-and-buildings.md) · [Index](README.md) · Next: [Units and training →](05-units-and-training.md)

## Resources

| Resource | Used for |
|---|---|
| Wood | Buildings, roads, bridges, siege engines |
| Stone | Buildings (walls above all), roads, forts |
| Grain | Feeding troops and armies, settlers, terraforming, the Shrine's offering |
| Iron | Weapons: most troops, the Blacksmith, higher buildings |
| **Svarog's Ember** | Rare. The bridge, Ember techs, the Shrine ([page 11](11-research-faith-smithing.md#svarogs-embers)) |

Each village keeps its own stores. Resources move between villages, players
and the Holy City by **caravan**.

- **Computed when read.** Stores aren't ticked every second: each village
  keeps a *ledger* (amounts at a moment, plus rates), and the amounts are
  worked out when someone looks.
- **Capped.** Anything produced above storage is lost.

## Production

A village's hourly income of each resource is the sum of:

- **A base** of 9 wood, 6 stone, 8 grain and 3 iron per hour.
- **Its fields:** level 1 gives the building's base (15 wood, 12 stone,
  15 grain, 8 iron), ×1.35 per level above 1.
- **Producing buildings:** Fisherman's Hut, Ranch, the Granary-Temple.
- **Its outposts** ([below](#outposts)).

all multiplied by:

```
1 + production.<resource> + production.all     (bonuses, added together)
```

then by world speed.

Where production bonuses come from:
- **Research** ([page 11](11-research-faith-smithing.md#research)).
- **Lore scrolls.**
- **Clan and hero.**
- **The Shrine** of Dazhbog or Veles.
- **Buildings:** Forester, Stonemason, Mill, Smelter, Workers' Huts, Water
  Wheel, Windmill, Mountain Lodge.
- **The bridge:** the first stage's blessing, +10% of everything.
- **Mountain cities:** +10% each, for every member ([page 13](13-events-and-raids.md#the-mountain-city)).

## Outposts

- **Claiming.** An outpost is claimed on a resource hex within **2 hexes** of
  the village. A village may hold 1 outpost, plus 1 for every 2 Elder's Hall
  levels.
- **Upgrading.** Outposts go up to level 5. Cost: 150 / 100 / 80 / 40 (×1.7 a
  level). Time: 15 min (×1.6 a level).
- **Yield.** Hourly yield at level 1, ×1.35 for every level above:

| Terrain | Outpost | Yield per hour |
|---|---|---|
| Plains | Farmstead | 10 grain |
| Forest | Sawmill | 10 wood |
| Hills | Quarry | 6 stone, 4 iron |
| Wooded hills | Woodland camp | 5 wood, 4 stone, 2 iron |
| Mountain | Mine | 6 stone, 6 iron |
| Lake | Fishing boat | 8 grain |

On top of that:
- **Roads.** The road bonus adds up to +30% ([page 2](02-map-and-movement.md#roads)).
- **Research.** `outpostYield`: Frontier Steadings +20%, Frontier Tithes +25%.
- **Sieges.** Outposts produce nothing while their village is besieged.
- **Hordes.** A marching horde **burns every outpost within its raid reach of
  its road down a level**: 1 hex for most fronts, 2 for the East's nomads.
- **Fire** burns outposts to ruins ([page 2](02-map-and-movement.md#fire)).
- **Rebuilding.** A standing order can rebuild raided outposts
  ([below](#standing-orders)).

## Storage

Every village holds a base of **1,000** of each resource.

| | Adds per building at level L | At level 10 | At level 20 |
|---|---|---|---|
| Storehouse (any resource) | 1,000 × (1.3^L − 1) | ~12,800 | ~189,000 |
| Grain Silo (grain only) | 1,000 × (1.3^L − 1) | ~12,800 | ~189,000 |

- **Several of each.** A village can build more than one; they add up.
- **Bonuses.** `storage` bonuses add their share of capacity: Granary Lofts
  +25%, Royal Granaries +25%, the Weave of Mokosh scroll +10%, Mikula +10%,
  the Shrine of Mokosh +5% a level.

## Grain upkeep

Every unit eats grain every hour (its `upkeepPerHour`: 1 for most troops, up
to 4 for the mightiest).

| Where the unit is | Eats |
|---|---|
| In the garrison (home or in training) | 25% of its upkeep, from the village |
| Quartered in a settlement, fort or supply point | 50%, from that place's granary |
| Marching, or standing on open ground | 100%, from the army's own grain |
| Away on an errand (scouts, settlers, caravan escorts) | 100% |

- **Bonuses.** `upkeep` changes it (negative means they eat less): Field
  Kitchens −10%, Veles's Ward −10%, Svarog's Living Flame −10%, the
  Granary-Temple and Longhouse Hall, Veles at the Shrine. Some clans and
  heroes eat more (Zmija +10%, Dobrynya +8%, Svyatogor +10%).
- **Running a realm.** Each village after the first costs grain upkeep too:
  the n-th village founded pays (n − 1) × 3 grain an hour.

How armies carry and draw grain is on [page 8](08-armies-and-field.md#grain-and-supply).

## The Market

- **Trading.** One resource for another, at a rate of **40%** at level 1 plus
  4% a level (116% at level 20). At 40%, 100 wood buys 40 iron. Bonus:
  Lisica clan +15%.
- **Selling gear.** It buys a spare piece of the hero's gear for 150 wood,
  150 stone, 150 grain and 100 iron. Gear the hero wears must be taken off
  first.

### The bounty board (co-op only)

A village with a Market posts offers to other players: several resources
offered, several others asked in return.

- **Posting.** What it offers, plus a **10% fee** on it, leaves the village at
  once.
- **Taking.** Another player takes it from one of their villages, paying what
  is asked and receiving what is offered, both at once.
- **The poster's share.** The poster's village receives what was asked, less
  10%. Example: 1,000 wood offered for 500 iron. The poster pays 1,100 wood
  and gets 450 iron; the taker pays 500 iron and gets 1,000 wood.
- **Limits.** A Market keeps 1 open bounty, plus 1 every 3 levels above 1.
  Each offers and asks at most 500 × the Market's level.
- **Calling it off.** A bounty can be called off: the offer comes back, the
  fee doesn't.

## Caravans

The **Caravan Yard** gives one caravan per level.

| | |
|---|---|
| Capacity | 500 resources in total per caravan (several go together for a bigger load) |
| Speed | 5 hexes/h on plains |
| Bonuses | `caravanCapacity` and `caravanSpeed` (research, Bobr clan, Sadko, scrolls, gear) |

Caravans:

- **Send.** Carry resources to a teammate's village, your own settlements,
  your forts and supply points (grain only), or the Holy City vault.
- **Bring back.** When sent to your own settlement or store, they can also
  carry something home.
- **Turn on the road.** One going out finishes the hex it is crossing and
  comes home with its load, or is sent somewhere else. One already coming
  home can't be turned.
- **Get ambushed.** Passing within 1 hex of a bandit camp, it is attacked
  unless its **escort's attack** reaches the camp's. If not, it loses half its
  load and the escort loses 30% of its troops.

### Merchants

- **The trip.** A **merchant caravan** goes out empty from a village with a
  Caravan Yard to any other settlement (or the Holy City) by the fastest road
  and back, trading along the way.
- **The pay.** It brings home **20 of each resource for every hex it travels,
  out and back**: 10 hexes away, that is 400 of each. It is paid as it turns
  for home, so a camp can ambush it on the way back.
- **One at a time.** It takes one of the yard's caravans. Afterwards the
  player's merchants rest 12 game hours, 0.18 h less for every Caravan Yard
  level above 1 of the sending village, never under 8.5 h.

## The Holy City vault

The group's shared store, safe until the Holy City falls.

| | |
|---|---|
| Level 1 capacity | 3,000 of each resource |
| Each level | capacity ×1.5, up to level 10 |
| Upgrade cost | 800 / 1,000 / 400 / 400 at level 2, ×1.6 a level, paid from the vault |
| Upgrade time | 1 h at level 2, ×1.35 a level |

- **Filling it.** Caravans bring resources in.
- **Taking out.** Any member can send a withdrawal to their village by caravan,
  with travel time.
- **The bridge** draws its costs from the vault ([page 14](14-bridge-and-endgame.md)).

## Standing orders

Rules that run by themselves every 20 game minutes, for villages that have any:

| Order | What it does |
|---|---|
| Repeat training | Keeps a unit topped up to a target number in the village |
| Rebuild | Restores raided outposts to the best level they had |
| Surplus | Sends whatever is above a chosen share of storage (30–95%) to the vault, at least 100 in all, with the caravans at home |
| Supply route | Keeps one of the owner's forts or supply points stocked to N grain from the village, sending at least 50 at a time (counting grain already on the way) |

A village keeps up to 3 standing orders, plus 1 every 3 Elder's Hall levels.
