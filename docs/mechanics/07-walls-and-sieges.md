# 7. Walls and sieges

[← Battles](06-battles.md) · [Index](README.md) · Next: [Armies in the field →](08-armies-and-field.md)

A village's walls make a horde fight on the village's terms: they toughen the
garrison, give its archers a platform and hold back the horde's fighters
until they are battered down or climbed.

## The walls

- **The plot.** The walls are their own building (plot `w`), up to level 10.
  Cost: 216 / 360 / 48 / 48 at level 1, ×1.5 a level. Time: 9 min 48 s,
  ×2.1025 a level.
- **Material.** As they rise, the walls change material:

| Wall levels | Tier | Toughness |
|---|---|---|
| 1 | Palisade (wood) | ×1.0 |
| 2 | Timber Rampart | ×1.15 |
| 3 | Stone Wall | ×1.35 |
| 4+ | Fortress Walls | ×1.6 |

- **Integrity** is **240 per level** × the tier's toughness. It is what the
  horde must batter down.
- **Defense.** While they stand, the walls add **+6% defense per level** to
  the garrison and the armies fighting with it.
- **Manning.** The walls hold **60 men a level**, archers first. Archers on
  the walls shoot **+8% harder per wall level**.

### Towers

Wall slots t0–t4 open at wall levels 1, 2, 3, 4 and 5. Each slot holds a
tower (each up to level 10; effects are per level):

| Tower | Effect per level |
|---|---|
| Archer Tower | Garrison attack +10% while the walls stand |
| Gate Tower | Wall integrity +16% |
| Ballista Platform | Smashes 0.7 of the horde's siege engines each round before the assault |
| Murder Holes | Garrison defense +8% while the walls stand |
| Moat (ditch) | Battering −10%, engine building +20% slower, climbers −12%. Dry at level 1, then it holds water |
| Watchtower | Hordes are seen 2 game hours sooner: the warning push comes earlier |

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
- **The moat** cuts battering by 10% a level.
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
  engine's own setup factor. The moat slows it 20% a level.
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

## The Holy City

The Holy City has no walls to build. Its guard fights from the city in a
defensive stance with the home bonus ([page 1](01-world-and-run.md#the-holy-city-and-sanctity)).
Armies standing there fight with it.
