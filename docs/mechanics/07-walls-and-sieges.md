# 7. Walls and sieges

[← Battles](06-battles.md) · [Index](README.md) · Next: [Armies in the field →](08-armies-and-field.md)

A village's walls make a horde fight on the village's terms: they toughen the
garrison, give its archers a platform and hold back the horde's fighters
until they are battered down or climbed.

## The walls

- **The plot.** The walls are their own building (plot `w`), up to level 10.
  Cost: 216 / 360 / 48 / 48 at level 1, ×1.5 a level. Time: 4 min, ×1.45 a
  level.
- **Material.** As they rise, the walls change material:

| Wall levels | Tier | Toughness |
|---|---|---|
| 1–2 | Palisade (wood) | ×1.0 |
| 3–4 | Timber Rampart | ×1.15 |
| 5–7 | Stone Wall | ×1.35 |
| 8+ | Fortress Walls | ×1.6 |

- **Integrity** is **120 per level** × the tier's toughness. It is what the
  horde must batter down.
- **Defense.** While they stand, the walls add **+3% defense per level** to
  the garrison and the armies fighting with it.
- **Manning.** The walls hold **30 men a level**, archers first. Archers on
  the walls shoot **+4% harder per wall level**.

### Towers

Wall slots t0–t4 open at wall levels 1, 3, 5, 7 and 9. Each slot holds a
tower (each up to level 10; effects are per level):

| Tower | Effect per level |
|---|---|
| Archer Tower | Garrison attack +5% while the walls stand |
| Gate Tower | Wall integrity +8% |
| Ballista Platform | Smashes 0.35 of the horde's siege engines each round before the assault |
| Murder Holes | Garrison defense +4% while the walls stand |
| Moat (ditch) | Battering −5%, engine building +10% slower, climbers −6%. Dry until level 4, then it holds water |
| Watchtower | Hordes are seen 1 game hour sooner: the warning push comes earlier |

## Escalade: getting over the walls

- **Held back.** While the walls stand, the horde's **fighters** (not its
  archers) strike at **50%**: they can't reach the defenders.
- **Climbers.** Climbing engines (scaling ladders, siege towers) carry men over
  the walls each round: a ladder 8, a siege tower 30. Those carried over strike
  at full strength.
- **How many.** A horde that builds climbers builds enough to carry 60% of its
  fighters. The moat keeps some off.

## Battering the walls

- **Siege power.** Every enemy unit batters the walls each round with its
  `siege` value. Units without one batter at 2% of their attack. Dedicated
  attackers: Cave Bear 3, Div 10, Zmey Whelp 8, Siege Ram 40, Catapult 60.
  The Avatar of Černobog batters at 60, the Leshen at 40.
- **The moat** cuts battering by 5% a level.
- **Breaching.** When integrity reaches 0, the walls are breached: they lose
  **one level**, and from then on they give no defense, archer platform or
  hold-back for the rest of the battle.

## Siege engines built on site

A horde that couldn't breach within **6 rounds** stops and builds its front's
engine on site:

| Front | Engine | Siege craft |
|---|---|---|
| North | — (monsters build none) | 0 |
| East | Scaling Ladders (climbers) | ×1.6 |
| South | Siege Ram (battering) | ×0.8 |
| West | Siege Tower (climbers) | ×0.8 |

- **Time.** Building takes 3 game hours × the front's siege craft × the
  engine's own setup factor. The moat slows it 10% a level.
- **Ballistae** smash engines before the horde closes in.
- **Engines on the march.** Later hordes of the Order may bring rams,
  catapults and siege towers with them (from waves 10, 13 and 15, in bigger
  groups).

### Volley rounds

While the horde builds its engines before standing walls, each round is a
**volley round**:

- **Archers only.** Only the archers of both sides shoot. Nobody else
  strikes, and the walls are not battered.
- **Free rounds.** Volley rounds don't count against the battle's 12 rounds.
- **No fall.** The village can't fall in a volley round, though the horde can
  be beaten in one.
- **Arriving armies.** An army arriving during a volley round falls on the
  horde with everything it has: its hand-to-hand fighters strike too.

## Charging out

While a horde fights at your standing walls, you can order the garrison and
the armies with it **out of the walls**. From the next round:

- **In the open.** The fight is in the open: no wall defense, no shooting from
  the walls.
- **No hold-back.** The horde's fighters are no longer held back.
- **The walls are spared.** They are neither battered nor breached.
- **No more waiting.** A horde still building engines is fought at once.

There is no going back inside for that battle.

## Hammer and anvil

A reinforcement reaching a village whose walls still stand falls on the horde
pinned against them, whatever side it comes from. See
[reinforcements](08-armies-and-field.md#reinforcements).

## Walls along the edges

Walls can also run along the **edges between two hexes**, like rivers. A
village builds them out in the land, and raises each one tier by tier.

- **Where.** On an edge with either hex within **4 hexes** of the village, or
  in the zone of one of its forts ([page 17](17-forts.md#the-keeps-zone-of-influence)).
  Both hexes must be land an army can enter (not mountains, lakes or the
  enemy lands). The Holy City's edges can be walled too.
- **Along a river.** A river edge holds a wall on **each bank**: the wall
  stands on the bank of the hex it is built from, and the other bank can
  have its own (a gatehouse on one, a wall on the other, or two of either).
  Players' armies pass only where every wall on the edge is a gatehouse. A
  horde crossing there tears down both, the hours of each added together.
- **Tiers.** Each tier is raised on a standing wall. The first tier is mostly
  wood, the second wood and stone alike, the third mostly stone. Every tier
  needs grain for the workers:

| Tier | Wall | Cost (wood / stone / grain / iron) | Time | Horde tears it down in |
|---|---|---|---|---|
| 1 | Palisade | 400 / 40 / 120 / 0 | 1 h | 2 h |
| 2 | Timber-and-stone wall | 450 / 450 / 180 / 30 | 2 h | 4 h |
| 3 | Stone wall | 120 / 900 / 240 / 60 | 3 h | 7 h |

- **Gatehouses.** A gatehouse is a wall with gates. It costs **twice** the
  wall's materials, plus **400 / 700 / 1,000 iron** for the gates at tiers
  1 / 2 / 3. Building it takes **1.5×** as long, and tearing it down takes a
  horde **1.5×** as long (3 h / 6 h / 10.5 h).

| Tier | Gatehouse cost (wood / stone / grain / iron) | Time |
|---|---|---|
| 1 | 800 / 80 / 240 / 400 | 1.5 h |
| 2 | 900 / 900 / 360 / 760 | 3 h |
| 3 | 240 / 1,800 / 480 / 1,120 | 4.5 h |

- **Nobody crosses a wall.** Armies, caravans, scouts, settlers and heroes
  go round it. A wall still being built for the first time is no
  obstacle yet. An army already on the march keeps its road.
- **Gatehouses let players through.** Every player's armies, caravans and
  scouts pass a gatehouse as if it were open ground. Hordes don't.
- **Hordes tear walls down** when going round would take longer. When a
  horde plans its road, a wall in the way costs the hours it takes to tear
  down. If that is quicker than the way round, the horde marches up to the
  wall, spends those hours, and the wall is **gone** once it is through. The
  owner hears of it. A wall finished across a marching horde's road makes it
  plan its road again from the hex it is heading for.
- **Tearing your own down.** The owner can tear a wall down at any time.
  Nothing comes back.
- **A gatehouse on a fort's hex** becomes that fort's outermost wall ring
  ([page 17](17-forts.md#the-gatehouse-ring)).

The map draws each tier differently: sharpened stakes, timber posts on a
stone footing, or crenellated stone. A gatehouse shows iron gates between
two towers.

## The Holy City

The Holy City has no walls to build (walls can still run along its edges,
[above](#walls-along-the-edges)). Its guard fights from the city in a
defensive stance with the home bonus ([page 1](01-world-and-run.md#the-holy-city-and-sanctity)).
Armies standing there fight with it.
