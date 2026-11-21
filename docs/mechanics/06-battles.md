# 6. Battles

[← Units and training](05-units-and-training.md) · [Index](README.md) · Next: [Walls and sieges →](07-walls-and-sieges.md)

Battles are automatic and deterministic: the same inputs and the same battle
seed always play out the same way. What players control is everything before
and around the fight:
- **Who fights:** troops and leaders.
- **How they fight:** stances.
- **Where they fight:** the [terrain](#terrain), walls ([page 7](07-walls-and-sieges.md))
  and field setups ([page 8](08-armies-and-field.md#field-setups)).
- **When help arrives:** reinforcements ([page 8](08-armies-and-field.md#reinforcements)).

## Rounds

- **Length.** A battle is fought in **rounds of 10 real minutes**, whatever
  the world speed, so help can arrive while it goes on.
- **At most 12 rounds** (2 hours). If neither side has broken by then, the
  defenders hold.
- **Both sides strike at once** in a round, each with the numbers it had when
  the round began.
- **Joining.** Reinforcements that arrive join at the next round.
- **Volley rounds** at standing walls don't count towards the 12
  ([page 7](07-walls-and-sieges.md#volley-rounds)).

## The damage formula

Each round, every unit type on the attacking side strikes every target type
on the other side. For one target type:

```
damage  = Σ over striking types:
            count × attack × roll × stance attack × matchup × counter
        (+ each champion's attack × stance attack × matchup)
        (+ burning owed from earlier rounds)

aimed   = damage × (target's count / all targets' count)

lands   = aimed × 100 / (100 + target's defense × roll)

fallen  = lands / (target's health × target's stance defense × home bonus)
```

- **Rolls.** Each striking unit type rolls 1 ± 25% for the round. Each target
  type rolls its own 1 ± 25% on defense. Cards show these ranges: an attack of
  13 reads "10–16".
- **Spread.** Damage is spread over the targets by their share of the numbers.
  Champions count as one target each.
- **Armor.** Defense works like armor in an RPG: 100 / (100 + defense) of the
  damage gets through. Defense 100 lets half through and 300 a quarter, so
  every extra point counts for less.
- **Rounding.** The fraction of a casualty is rolled: 2.4 deaths means 2, or 3
  with a 40% chance. Small fights still take losses on average.
- **The home bonus** (×1.2 health) applies to defenders in their own village,
  the Holy City and a camp behind its palisade.

### Attack and defense bonuses

A player unit's numbers are multiplied before the battle:

```
attack  = base × (1 + attack.all + attack.<family> + forged attack)
defense = base × (1 + defense.all + defense.<family> + homeDefense (at home) + forged defense)
health  = base × (1 + forged health)
```

- **Sources:** research, lore scrolls, the clan, the hero's own effects,
  skills and gear (in the hero's village or army), a general's levels, the
  Shrine, bridge blessings, the Ranch, scout intel.
- **The Blacksmith's** forged levels count per unit ([page 11](11-research-faith-smithing.md#the-blacksmith)).
- **Situational:** walls, field setups, pincer and hammer bonuses multiply on
  top.
- **Enemy units** are scaled by their leader's skills, their front's hatred
  and their own conditions (a river, ambush, choke point).

## Terrain

Where a battle is fought changes how hard each side hits and holds. The
battle's hex decides it: a village's own hex, the field hex, the camp, the
site. Raids beyond the map's edge have no terrain.

**What the hex counts as.** Plains, steppe, ice, Hallowed Lands and the Holy
City are *open ground*. Forest and Dark Forest are *woods*. Hills and a
mountain city are *hills*. Wooded hills are both woods and hills. Swamp is
*wetland*.

**What lies beside it.** Each mountain next to the hex counts, and each river
along one of its six edges or lake next to it counts as *water*. Mountains
and waters each count **at most twice**: three mountains beside a battle give
the same as two.

**Unit families** (every side, hordes included):

| Family | Open ground | Woods | Hills | Each mountain beside |
|---|---|---|---|---|
| Cavalry | +30% attack | | | |
| Infantry | | +10% attack | +20% attack | |
| Archers | +10% attack | −20% attack | +30% attack | +10% attack |

**Clans** add their own ([page 10](10-heroes-generals-clans.md#clans-on-their-ground)),
and some units have their own on top ([page 5](05-units-and-training.md)).

All the shares a unit gets add up, and the sum multiplies its attack or
defense:

```
attack  × (1 + family's + unit's own + clan's)
defense × (1 + unit's own + clan's)
```

Example: Rod Zmije's Serpent Axemen fight in a swamp with three rivers around
it. Attack: +20% (their own, wetland) = ×1.2. Defense: +20% (clan, wetland)
+ 2 × 10% (clan, water, counted twice) = ×1.4.

Champions are not affected by terrain.

## Stances

Every army, every garrison and every horde fights in a **stance**:

| Stance | Attack | Defense | Breaks at |
|---|---|---|---|
| Defensive | ×0.9 | ×1.35 | 45% lost |
| Balanced | ×1.0 | ×1.0 | 60% lost |
| Offensive | ×1.4 | ×0.9 | 35% lost |
| Hold the Line | ×0.9 | ×1.05 | never |

- **Choosing.** A garrison fights in its village's stance. Each army has its
  own, set when it is sent and changeable later.
- **The trade-off.** The earlier a stance breaks, the more it gives in the
  fight.
- **Hordes** pick their stance by their front's temperament. The North favours
  Offensive and the Order favours Hold the Line. A horde's stance stays hidden
  until a good scout report reveals it.

### Matchups

Some stances catch others off balance. The attacker's damage is multiplied by:

| Attacker's stance | against | × |
|---|---|---|
| Defensive | Offensive | 1.15 |
| Balanced | Defensive | 1.10 |
| Offensive | Balanced | 1.10 |
| Offensive | Hold the Line | 0.90 |
| Hold the Line | Offensive | 1.10 |
| Hold the Line | Defensive | 0.90 |

Every other pairing is ×1.

## Counters

A family strikes the family it beats at ×1.5:

- **Infantry** beat **cavalry**.
- **Archers** beat **infantry**.
- **Cavalry** beat **archers**.

Units with their own counters (Horse Cutter ×2 against cavalry, Poison Archer
×1.8 against infantry…) use those instead. Siege engines with empty counters
get no bonus at all.

## Breaking

- **The threshold.** A side **breaks** once it has lost its stance's share of
  the troops it started with. Hold the Line never breaks.
- **A horde's nerve** scales its threshold, capped at 95%. Monsters ×1.15,
  the Order ×1.25, nomads ×0.85, and a leader's Dread skill adds more.
- **The players' side** doesn't break as one:
  - **Each army** fights in its own stance and breaks on its own losses since
    it joined. It falls back home beaten: its hero is wounded and its general
    killed.
  - **The garrison** fights in the village's stance. Once it breaks, it stops
    fighting.
  - **The defenders lose** once every army and the garrison have broken or
    fallen.
- **How it ends.** The horde wins when the defenders have all broken or
  fallen. The defenders win when the horde breaks or is wiped out. If both
  fall in the same round, the defenders hold.

## Champions: heroes and generals in the ranks

Heroes and generals don't just lead: each fights as a **champion**, one
mighty warrior who strikes and can be struck down.

| | Attack | Defense | Health | Per level above 1 |
|---|---|---|---|---|
| Hero | 150 | 80 | 1,600 | +10% |
| General | 90 | 55 | 1,000 | +8% |

- **Who commands.** One commands a force: its hero, else its general. The
  commander's effects apply to the troops ([page 10](10-heroes-generals-clans.md)).
- **When a hero falls,** they are carried home **wounded**, and the general
  with them takes command for the rest of the battle.
- **A general who falls** is dead.
- **Champions don't counter.** Their strikes ignore family counters.
- **Stronger champions.** Svyatogor's champion is 60% stronger. Marya's
  generals are 30% stronger.

## Burn and poison

Some units' blows leave something behind:

| Affliction | Effect |
|---|---|
| **Burn** | 10% of the burning unit's blow hurts the same side again in each of the next **3 rounds**, spread over its troops like any blow and going through armor |
| **Poison** | A side struck by a poisoner fights at **85%** of its attack and defense for the next **2 rounds** (each new poisoned blow starts the 2 rounds again) |

- **Player units:** Poison Archers and Poison Hunters poison. The Blacksmith
  forges **fire arrows** (burn) for archers and siege engines and **poisoned
  blades** (poison) for infantry and cavalry ([page 11](11-research-faith-smithing.md#fire-arrows-and-poisoned-blades)).
- **Enemies that burn:** the Firebird, Zmey Whelp, Fire Archer and Fire Priest.
- **Enemies that poison:** the Upyr and Steppe Shaman.
- **Carried between rounds.** Battles fought round by round (at villages, in
  the field, at the Holy City) keep what burns and poisons between rounds.
  Fights resolved at once (camps, raids, shipyard raiders) carry it from round
  to round inside the fight.

## Who fights

- **Support units stay out.** Scouts, healers and wagons don't fight and
  aren't struck ([page 5](05-units-and-training.md#support-units)).
- **Wagons in a wagon fort** do fight, as a wall: the share of the blows aimed
  at their side's archers falls on the wagons instead, split among the wagon
  kinds by their numbers, while any wagon stands.

## Healing

- **The Hospital:** when a garrison holds its own village, 5% a level of its
  fallen get up again.
- **Shamans:** each gives every fallen soldier of its side a 5% chance to
  rise, at most 50% ([page 5](05-units-and-training.md#healers)).

## What victory brings

| Battle | Spoils |
|---|---|
| Village defended | The hero's XP from the kills, a 40% chance of hero gear, fear left on that place for the horde AI ([page 9](09-hordes-and-threats.md#fear)) |
| Village raided | The horde carries off up to 30% of the stores (×its front's greed and leader's Greed), less the more of it fell; less again with `lootTaken` bonuses such as Hidden Cellars (−25%) |
| Village razed | A ruin ([page 3](03-villages-and-buildings.md#ruins-and-rebuilding)) |
| Camp cleared | 15 wood, 15 stone, 15 grain and 8 iron for every camp unit, carried home; a 35% gear chance; a lair also a 75% chance of a Svarog's Ember |
| Raid battle won | Loot per kill, the stronghold's stores ([page 13](13-events-and-raids.md#raids-beyond-the-edge)) |

**Raid loot** is limited by what the army can carry: the sum of each unit's
`carry` (30–120 for most troops, 400 for a Military Caravan, 600 for a large
one).

## Battle reports

- **Every battle leaves a report:** each round's losses on both sides, who
  joined and who broke, and the key modifiers (Ambush +30%, Pincer +18%, the
  walls…).
- **On the map,** a battle under way shows two swords clashing over its hex.

## Hordes fighting together

A horde reaching a hex where another horde is already fighting (a village,
the Holy City or a field battle) joins that battle instead of starting its
own. Its troops add to the attackers. A bridge quest's host keeps to its own
errand.
