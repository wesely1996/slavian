# 2. Map, movement and terrain

[← The world and the run](01-world-and-run.md) · [Index](README.md) · Next: [Villages and buildings →](03-villages-and-buildings.md)

## Terrain

Each hex has a terrain. Its **move cost** is what it costs to *enter* it.
Impassable terrain has none.

| Terrain | Move cost | Settle? | Notes |
|---|---|---|---|
| Plains | 1 | Yes | Grain outposts; ranch site |
| Forest | 2 | Yes | Wood outposts; ambush ground |
| Hills | 2 | Yes | Stone and iron outposts; ambush ground; windmill site |
| Wooded hills | 3 | Yes | A little of each resource; ambush ground |
| Swamp | 3 | No | Ambush ground; can be drained |
| Mountain | impassable | No | Rich stone and iron outposts; a road makes a **pass** (move cost 8 before the road's factor) |
| Lake | impassable | No | Grain outposts (fishing boats); sailed once a river boat is built |
| Holy City | 1 | No | The centre |
| Mountain City | 2 | No | A mountain hex while a mountain city stands there ([page 13](13-events-and-raids.md#the-mountain-city)); hordes never enter it |
| Ocean | impassable | No | Edge belt of an inactive side |
| Dark forest | 3 | No | Edge belt, North spawn |
| Ice | 3 | No | Edge belt, North spawn |
| Steppe | 1 | No | Edge belt, East spawn |
| Hallowed Lands | 2 | No | Edge belt, South and West spawn |

**Choke point:** any passable hex with at least 3 impassable neighbours
(mountain, lake, ocean). It matters in field battles ([page 8](08-armies-and-field.md#field-setups)).

## How travel time is worked out

Everything that moves takes the cheapest road by total move cost: armies,
caravans, scouts, settlers, heroes and hordes. Time in game hours is:

```
time = Σ (move cost of each hex entered) / speed
```

where speed is hexes per hour on plains.

- **An army** moves at its slowest *walking* unit. Units riding in wagons
  don't count ([page 5](05-units-and-training.md#wagons-and-transports)).
- **Forged speed.** A Blacksmith's "Better harness" raises a unit's speed
  ([page 11](11-research-faith-smithing.md#the-blacksmith)).
- **Pathfinders** in an army take 5% each off the extra cost of harsh terrain
  (whatever is above cost 1), at most 50%.
- **Hungry armies** march at 75% speed ([page 8](08-armies-and-field.md#attrition)).
- **Caravans** move at 5 hexes an hour, faster with `caravanSpeed` bonuses.
- **Heroes and generals** travel at 6 hexes an hour on their own.

## Roads

A village builds roads between two neighbouring hexes within **4 hexes** of
it. Each road has three levels, each paid from the village and built over
time. Moving along a road costs the road's **factor** times the terrain's
move cost:

| Level | Look | Factor | Outpost bonus | Cost (w/s/g/i) | Build time |
|---|---|---|---|---|---|
| 1 | Dirt track with wheel ruts | ×0.5 | +10% | 150 / 250 / 50 / 0 | 30 min |
| 2 | Stone road (gravel) | ×0.35 | +20% | 200 / 350 / 75 / 25 | 45 min |
| 3 | Paved road between kerbs | ×0.25 | +30% | 300 / 500 / 100 / 75 | 60 min |

Build times are game time and shrink with world speed.

- **While being improved.** A road keeps its old level until the work is done.
- **Who uses roads.** Players and the human hordes (East, South, West) use
  them alike. The **Monsters of the North keep off roads.**
- **Fire** doesn't damage roads ([below](#fire)).
- **Outpost bonus.** An outpost joined to its village by road gathers more.
  The game takes the route with the fewest road steps between the two (of
  those, the best built), and adds the *average* level bonus of its steps to
  the outpost's yield. Three steps of paved road add +30%.

### Mountain passes

- **Cost.** A road may be cut into a mountain hex. Each level of such a
  road costs **3×** as much and takes **3×** as long to build.
- **Crossing.** Along the road, the mountain costs 8 × the road's factor to
  enter: 4 on a dirt track, 2 on a paved road.
- **Off the road** the mountain stays impassable. No army can stop on a
  pass, and hordes keep off them.
- **On the map** passes are drawn as switchbacks climbing over the mountain.

## Rivers and bridges

- **No crossing without a bridge.** Rivers run along hex *edges*, and nothing
  crosses one except where a bridge stands. That includes hordes.
- **Building one.** A village builds a bridge over a river edge within 4 hexes
  of it. Cost: 800 wood, 600 stone, 100 grain, 150 iron; it takes 2 game hours.
- **Defending one.** A horde that crossed a river (over a bridge) into the hex
  it fights in strikes at **80%** there, at walls or in the field.
- **Water buildings.** A village beside a lake, or with a river on one of its
  six edges, may build the Fisherman's Hut and the Water Wheel
  ([page 3](03-villages-and-buildings.md#terrain-buildings)).

### River boats

A **shipyard** event ([page 13](13-events-and-raids.md#shipyards-and-river-boats))
builds a boat on a river.

- **Faster lanes.** Once it is done, armies, caravans and scouts stepping
  between two hexes beside that river move **3×** as fast, for the rest of the
  run. This covers every river edge joined to the one it was built on.
- **Lakes.** A lake the river reaches is sailed too: its hexes cost 1 to
  enter before the lane's ×3, and its shores and the rivers flowing into it
  join the lane. No army can stop on a lake.

## Fog of war

- **What you see.** Hexes come into view around villages, outposts, armies
  and scouts.
- **What stays.** Terrain, once seen, stays known. Enemies are only shown
  while something of yours can see them.

## Terraforming

A village can reshape the land within **2 hexes** of it.

- **Where.** On a hex with no village, outpost, fort, camp or site, and no
  other work under way there.
- **Cost.** The work is paid at once, mostly in grain to feed the workers, and
  is done after its game hours.

| Work | Changes | Cost (grain) | Time | Brings home |
|---|---|---|---|---|
| Clear the forest | Forest → plains, wooded hills → hills | 400 | 8 h | 900 wood |
| Plant trees | Plains → forest, hills → wooded hills | 500 | 16 h | — |
| Drain the swamp | Swamp → plains | 600 | 16 h | — |
| Level the hills | Hills → plains | 700 | 24 h | 900 stone |
| Burn the forest | Forest → plains, wooded hills → hills | 100 | 6 h | — (the timber is lost) |

## Fire

Burning a forest is a weapon as well as a way to clear land.

- **Where it can be set.** On forest or wooded hills only, and never where an
  army stands.
- **Nothing enters while it burns.** For its 6 game hours, no army, caravan,
  scout or horde can enter the hex. Those already on a road into it plan
  their way again from where they are: round it, or wait at its edge until it
  is out, whichever gets them there sooner.
- **It spreads.** One game hour after a hex catches, each neighbouring forest
  or wooded-hills hex catches too with a **20% chance**. It spreads at most
  **2 hexes** from where it was set.
- **What stops it.** Villages never burn, and a hex where an army stands
  stops the fire.
- **What burns.** On every hex the fire reaches:
  - **Outposts** are burnt to ruins, whoever owns them.
  - **Forts** and **supply points** are destroyed, with their grain.
  - **Bandit camps and lairs** are destroyed.
  - **Any other terraforming work** under way there is lost.
  - **The terrain** becomes plains (or hills), and the timber is lost.
- **What doesn't burn.** Roads, ruins, ancient sites, shipyards and the
  mountain city (none of those stand on forest).
- **Who is told.** Owners of a burnt outpost or fort get a push at once. The
  player who set the fire is told when it burns out.
