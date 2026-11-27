# 8. Armies in the field

[← Walls and sieges](07-walls-and-sieges.md) · [Index](README.md) · Next: [Hordes and threats →](09-hordes-and-threats.md)

## Armies and garrisons

- **Garrison:** the troops at home in a settlement (and those in training).
  They eat a quarter of their upkeep and fight its battles.
- **Army:** troops out of their settlement, on the map. An army is raised
  from a village's garrison and drawn as a banner with its symbol and its
  number of troops.
- **Home:** an army's home is the settlement it was raised in. It can be
  moved to another of your settlements.
- **A home in ruins:** when an army's home is razed
  ([page 9](09-hordes-and-threats.md#raid-or-raze)), it finds another place:
  - **Your nearest standing village,** measured from where the army is,
    becomes its home. An army on its way home turns there at once, and an
    army called home later goes there.
  - **None left?** It goes to your **refugee camp**, which becomes its home.
  - **No refugee camp either?** It marches to the **nearest ally's village**
    and stands there in support.
- **Leaders:** an army has at most one hero and one general
  ([page 10](10-heroes-generals-clans.md)).

An army stays where it is sent until it is moved, marched into a settlement
or called home. Tick **Come home when done** and it comes home by itself once
its errand is finished.

## Orders

| Order | What the army does |
|---|---|
| Support | Stands in a village (yours or a teammate's) and fights its battles |
| Reinforce | Joins a battle under way there, then goes back |
| Harass | Strikes a horde for one round with a bonus, takes only 30% of its losses, and rides back (needs at least 60% cavalry) |
| Hold | Holds a hex and fights any horde whose road crosses it ([field battles](#field-battles)) |
| Clear | Storms a bandit camp or lair ([page 9](09-hordes-and-threats.md#camps-and-lairs)) |
| Explore | Searches an ancient site, fighting its guardians first ([page 12](12-scouting-and-expansion.md#ancient-sites)) |
| Raid / Strike | Marches beyond the map's edge ([page 13](13-events-and-raids.md#raids-beyond-the-edge)) |
| Attack / Raze | PvP worlds: storms another player's village to plunder or burn it ([page 15](15-player-vs-player.md)) |

More things you can do with an army:

- **Turn it on the road:** an army marching or coming home can be given a
  new hex or village, or (marching) be called home. It finishes the hex it is
  crossing, then takes the new road, at no cost. One in a battle can't be
  turned.
- **Merge** two of your armies standing on the same hex. You can't merge two
  that both have a general.
- **Split** a standing army: the picked troops become a new army there, with
  their share of its grain.
- **Join the garrison:** marched into one of your own settlements, an army
  either joins the garrison or stands there as an army.
- **Disband** a standing army.
- **Send it on an expedition:** a standing army out in the field or in a
  fort can set out on a raid or a strike from where it stands
  ([page 13](13-events-and-raids.md#expeditions-from-the-field)), or be moved
  onto a camp to storm it or a site to explore it.
- **Spoils go home.** What an army wins storming a camp or exploring a site
  goes to its home settlement at once. Raids and strikes carry their loot
  home at the end.

## Army groups

An army group is an army with a set make-up that raises and keeps itself up.
Make one in the Army sheet's **Army groups** tab with **Create army**.

- **What it is.** A name (yours, or "*home*'s Army"), a **home settlement**
  and the troops it should hold, by unit: soldiers and scouts, at most 1,000
  in all. A player keeps at most 10 groups. All three can be changed later.
- **Recruiting.** At once, and then every 20 game minutes, the group has
  what it lacks trained. It counts the troops in its army and those already
  on their way (in training for it, or marching to it). Each missing unit is
  trained in your settlement **closest to the army** (to its home while it
  has none) that can train it: its building high enough, room in its queue,
  your army slots, and resources for at least one. That settlement trains as
  many as it can pay for at once (all that are missing, else half, a
  quarter, ... down to one; at most a batch). It pays as for any training.
- **Only in safe places.** The group recruits while it has no army, and
  while its army stands in one of your settlements, forts or supply points.
  Out in the field, on the road or in a battle it doesn't.
- **Forming at home.** Until the group has an army, its trained troops go to
  its home: those trained there stand there at once as its army (quartered
  in the settlement), and those trained elsewhere march there and join it.
- **Reinforcements.** Once it has an army, troops trained where it stands
  join it there; troops trained elsewhere march to where it stands, or where
  it is going, and join it when they reach it. If it has moved on meanwhile,
  they follow; if it is lost, the first to arrive become its new army.
- **The army is an army.** Move it, merge it, split it or send it out like
  any other. Troops beyond the make-up stay in it. If the army is lost or
  joins a garrison, the group forms again at its home.
- **Disbanding a group** leaves its army standing as a plain army; troops in
  training for it join their garrison, and those on the way stand wherever
  they arrive.
- **Rally points.** Troops trained for a group go to the group, never to the
  rally point ([page 17](17-forts.md#rally-point)).

## Grain and supply

An army carries its own grain.

- **Its supply.** Each unit marches out with its own `supplyHours` of upkeep:
  heavy infantry and engines 16–20 game hours, line troops 22–26, light
  infantry and skirmishers 28–32, riders 30–44, scouts 48. Military caravans
  add 200 or 300 grain on top.
- **Choosing how much.** When sending an army you choose how much grain it
  takes from the granary: at most what its troops can carry and what the
  granary holds. "Max" takes all it can carry.
- **Eating on the march.** Marching, or standing on open ground, it eats its
  full upkeep from what it carries.
- **Fallen soldiers' grain.** Men who fall leave their grain with the
  survivors while the army stands. When it sets off again it carries only its
  full supply.

### Quarters

An army standing in a settlement, a fort or a supply point is **quartered**:

- **Half price.** It eats **half** its upkeep from that place's granary,
  charged every game hour, and its own grain keeps.
- **Filling up.** Setting off from such a place, it first fills up to its full
  supply.
- **The floor.** Neither eating nor filling up takes the place's grain below
  its **floor**. By default that is the last grain everywhere; an owner can set
  another floor for a village or a fort.
- **At the floor,** the army eats its own grain again.

### Attrition

An army out of food:
- **Slows down,** marching at 75% speed.
- **Starts losing men** 8 game hours later: 5% of each unit (rounded up) every
  game hour.
- **Is lost** altogether after 24 game hours without food. Its general dies,
  and its hero is carried home wounded.

The army sheet shows its **fatigue**: fed, hungry and slower, or starving and
losing men, with a gauge to the moment it is lost.

## Reinforcements

- **Answering.** Every standing army has an **answer** toggle, on by default.
  When a battle starts within **3 hexes** of it, at a village, in the field or
  at the Holy City, it marches there as a reinforcement and goes back to where
  it stood once the battle is over. If it is beaten, it goes home instead.
- **Already there.** Armies standing in a village or on a fort fight its
  battles from the first round.
- **Arriving later.** Armies arriving during a battle join at the next round.

On its first round, an arriving army may get one of these bonuses (×its size
÷ the horde's size, capped):

| Bonus | When | Size | Max |
|---|---|---|---|
| **Pincer** | It arrives from a different side than the horde, at least 100° apart | ×0.6 | +30% |
| **Hammer and anvil** | It reaches a village whose walls still stand: it falls on the horde pinned against them, from any side (in place of the pincer) | ×0.8 | +40% |
| **Harassment** | Harass orders, at least 60% cavalry: strikes one round and rides off, taking only 30% of its losses | ×1.0 | +40% |

Each harassing strike makes the horde's front hate the more
([page 9](09-hordes-and-threats.md#hatred)).

## Field battles

An army **holding** a hex fights every horde whose road crosses it. Where it
holds matters:

### Field setups

| Setup | Requirement | Effect |
|---|---|---|
| **Ambush** | Forest, hills, wooded hills or swamp, with the army in place 60 game minutes before the horde arrives | The army's first round hits +30% harder (Rys and Vasilisa more), and the horde fights it without its stance |
| **Choke point** | A passable hex with at least 3 impassable neighbours | The horde strikes at 70%; Hold the Line gains +30% defense |
| **River** | The horde crossed a river (over a bridge) into the hex | The horde strikes at 80%, and the fight is on a narrow front ([page 16](16-battle-lines.md#ground-that-shapes-the-line)) |
| **Fort** | A fort on the hex | +30% defense and +30% attack for armies holding it; easier maneuvers ([page 16](16-battle-lines.md#ground-that-shapes-the-line)) |
| **Wagon fort** | The army circled its wagons ([below](#wagon-fort)) | Up to +30% defense |

### Forts

- **Building.** A village builds a fort within **4 hexes** of it, on open
  ground. Cost: 600 / 900 / 200 / 200 (Medvěd −20%, Sokol +30%). It takes 1
  game hour.
- **Defense.** Armies holding it get **+30% defense** and **+30% attack**.
  They maneuver more easily, the enemy less so, and by a river or lake they
  can't be encircled ([page 16](16-battle-lines.md#ground-that-shapes-the-line)).
- **A stronghold.** A built fort has its own buildings: a Keep, a Storage,
  a Fort Garrison and three wall rings with towers. Its own defenders hold
  it even with no army there, and a horde must batter its rings down one by
  one. It eats grain, and with no grain and no army for 12 game hours it
  falls to bandits ([page 17](17-forts.md)).
- **Grain.** Its Storage keeps 3,000 grain at level 1, more as it rises
  ([page 17](17-forts.md#grain-and-upkeep)). The grain is safe behind its
  walls: hordes don't burn it.
- **Sharing a hex.** A supply point and an outpost may stand on the same
  hex ([page 17](17-forts.md#sharing-a-hex)).
- **Zone of control.** While an army or its own defenders hold it, no
  horde steps onto a hex beside it. Hordes plan their road at least two
  hexes away. If that way round costs more than 50% more than the straight
  road, the horde attacks the fort first, then goes on. Forts channel
  hordes and make their attacks predictable. Hordes plan around the forts
  held when they set out (or re-plan, for a fire or a new road).
- **Fire** destroys it ([page 2](02-map-and-movement.md#fire)).

### Supply points

- **Building.** A grain store with no walls, built within **5 hexes** of a
  village. Cost: 300 / 150 / 100 / 0. It takes 30 game minutes.
- **Grain.** It keeps up to **6,000 grain**.
- **No defense.** It gives no defense. A horde marching onto it **burns it
  with all its grain**, unless an army stands on it.
- **Restocking.** Supply routes ([page 4](04-economy-and-logistics.md#standing-orders))
  keep forts and supply points stocked.
- **Filling armies.** An army arriving at or standing on a fort or supply point
  fills up from its grain as it would in a village. A standing army there can
  also leave grain from its own supply.

### Wagon fort

- **Where.** An army holding open ground (not a fort, supply point or
  settlement) with wagons can draw them into a ring. It is ready after **30
  game minutes**.
- **Defense:**

```
bonus = wagons × 10% ÷ ⌈soldiers ÷ 10⌉, at most +30%
```

  Example: 3 wagons with 25 soldiers give 3 × 10% ÷ 3 = +10%.
- **A wall before the archers.** Wagons in the ring fight (they don't otherwise
  fight at all): the blows aimed at the army's archers fall on the wagons
  while any stand ([page 6](06-battles.md#who-fights)).
- **Moving** the army breaks the ring up.

## Hordes passing through

A horde marching past one of your armies doesn't stop unless its road
crosses the army's hex. An army holding a hex therefore blocks a road. Fire,
rivers and passes shape which roads hordes can take
([page 2](02-map-and-movement.md)).

## Danger before an assault

Before sending troops at a camp or a guarded site, the game plays the
assault 30 times with what you know of the enemy and shows the likely
result in a word and a colour: Crushing / Clear / Close / Pyrrhic victory,
Close defeat, Defeat, Crushing defeat. Heroes and generals aren't counted.
