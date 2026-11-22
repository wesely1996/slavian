# Forts

A fort is a stronghold of its own out on the map. It has its own buildings
round a Keep, it eats grain, and it can fall to bandits. How a fort is
first built, the defense it gives the armies holding it, and its zone of
control over hordes are on [page 8](08-armies-and-field.md#forts). The
numbers here come from [`data/forts.json`](../../data/forts.json).

## Buildings

A fort has its own view, like a village's but smaller. In the middle
stand the **Keep**, the **Storage** and the **Fort Garrison**, with three
wall rings round them.
Each ring has its **wall** at the bottom and its **tower slots** along it:

| Ring | Opens at Keep level | Tower slots | Cost of its wall and towers |
|---|---|---|---|
| Inner wall | 1 | 1 | 50% of a village's |
| Middle wall | 4 | 3 | 75% of a village's |
| Outer wall | 7 | 4 | 100% of a village's |

- **A new fort** starts with the Keep and the Storage at level 1 and
  nothing else.
- **One at a time.** A fort raises one building at a time. The village
  that built the fort pays, and the work takes real time, divided by world
  speed.
- **Each level costs more:** the base cost × growth^(level − 1). Build
  times grow the same way.

| Building | Base cost (wood / stone / grain / iron) | Cost growth | Base time | Time growth | Highest level |
|---|---|---|---|---|---|
| Keep | 300 / 500 / 100 / 100 | 1.45 | 15 min | 1.35 | 10 |
| Storage | 250 / 150 / 0 / 20 | 1.4 | 10 min | 1.3 | 10 |
| Fort Garrison | 200 / 150 / 150 / 100 | 1.45 | 15 min | 1.35 | 10 |
| Wall (outer ring) | 180 / 300 / 40 / 40 | 1.5 | 4 min | 1.45 | 10 |
| Archer Tower (outer ring) | 160 / 120 / 30 / 60 | 1.55 | 3 min 20 s | 1.5 | 10 |

- **Walls and towers** cost a share of the village's walls and towers
  ([page 7](07-walls-and-sieges.md)): the inner ring half, the middle ring
  three quarters, the outer ring the full price.
- **The towers** are the village's six kinds: Archer Tower, Gate Tower,
  Ballista Platform, Murder Holes, Moat and Watchtower.
- **Building order.** A tower needs its ring's wall first, and never rises
  above it.
- **In battle** the walls and towers fight ring by ring
  ([below](#sieges)), on top of the fort's own bonus
  ([page 8](08-armies-and-field.md#forts)).

## Defenders

The **Fort Garrison** keeps the fort's own defenders. They never leave
the fort.

- **How many.** Each Garrison level keeps **2 spearmen, 2 archers and 1
  horseman**. At level 3 that is 6, 6 and 3.
- **Mustering.** While the fort has grain, **one fallen defender comes back
  every game hour**, free. The kind most short comes first. They come in at
  the fort's 4-hourly check, so a new Garrison fills up over a few checks.
- **Food.** Each defender eats **0.5 grain a game hour** from the fort.
  When the grain runs out, they **desert**.
- **Holding the fort.** A fort with defenders counts as held, even with no
  army there. Hordes keep out of its zone of control
  ([page 8](08-armies-and-field.md#forts)). A horde that marches on it
  fights the defenders.
- **In battle** they fight beside any armies holding the fort, in the
  defensive stance, with the fort's research and walls. Like a garrison,
  they stop fighting once they break.

## Sieges

A horde that fights at a fort meets its wall rings **from the outside in**,
one at a time.

- **Each ring** stands like a village's walls of its level
  ([page 7](07-walls-and-sieges.md)):
  - Integrity of 120 a level, times its tier's toughness.
  - The defense its level gives.
  - Room for archers on it.
  - The effects of the towers in its slots.
- **While a ring stands:**
  - Its ballistae smash engines.
  - The horde's fighters reach the defenders only where climbers carry them
    over.
  - Nobody maneuvers ([page 16](16-battle-lines.md)).
- **Breaching.** The horde batters the ring with its siege power each round.
  Once a ring is down, the next one in takes its place.
- **Afterwards.** When the battle ends, each ring that was breached loses
  **1 level**. The defenders left go back into the fort.

## The Keep's zone of influence

The village that built the fort can reshape the land and build roads
anywhere in the fort's zone, as if near its own walls
([page 2](02-map-and-movement.md#terraforming)):

| Keep level | 1–3 | 4–6 | 7–9 | 10 |
|---|---|---|---|---|
| Zone (hexes from the fort) | 1 | 2 | 3 | 4 |

## Grain and upkeep

- **Storage.** Each Storage level holds more grain: 2,000 + 1,000 a level.
  That is 3,000 at level 1 and 12,000 at level 10. The grain feeds the
  armies holding the fort ([page 8](08-armies-and-field.md#supply-points)),
  and supply routes and caravans fill it.
- **Upkeep.** A standing fort eats **5 grain a game hour, +2 for each Keep
  level, +0.5 for each defender**. It is counted every 4 game hours.
- **Taken by bandits.** A fort with **no grain and no army** holding it for
  **12 game hours** is taken by bandits. It becomes a bandit camp of 8 units
  ([page 9](09-hordes-and-threats.md#camps-and-lairs)). An army arriving, or
  grain brought in, stops the count.

## Sharing a hex

A fort, a supply point and an outpost may stand on the same hex. Only one
of each fits on a hex.

## Rally point

A fort can be your rally point instead of a village. Every batch of troops
trained in your settlements then marches there once done, and holds it.

## Tearing down

You can tear down any of your forts or supply points. Whatever grain it
held is lost. Armies standing there stay on the open ground.
