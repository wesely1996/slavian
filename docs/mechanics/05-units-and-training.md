# 5. Units and training

[← Economy and logistics](04-economy-and-logistics.md) · [Index](README.md) · Next: [Battles →](06-battles.md)

## Families and tiers

Every unit belongs to a **family**, which decides the counters in battle
([page 6](06-battles.md#counters)):

| Family | Trained in | Strong against (×1.5) |
|---|---|---|
| Infantry | Barracks | Cavalry |
| Archers | Shooting Range | Infantry |
| Cavalry | Stables | Archers |
| Scouts | Scout Lodge | — (never fight) |

- **Own counters.** Some units have their own counters instead of their
  family's. A Horse Cutter, for example, strikes cavalry ×2.
- **Tiers.** A unit's `requiresLevel` is the level its building needs to train
  it. Levels 1–3 are the first tier, 4–6 the second, 7–9 the third.

## Stats

| Stat | Meaning |
|---|---|
| Attack | Damage it deals, as a range: ±25% each round |
| Defense | Armor: only 100 / (100 + defense) of the damage aimed at it lands ([page 6](06-battles.md#the-damage-formula)) |
| Health | Damage it takes to fell one |
| Speed | Hexes per hour on plains |
| Upkeep | Grain per hour |
| Supply hours | Game hours of its own upkeep it carries when marching out with an army |
| Carry | Loot it carries home from a raid or a camp |

## The units

Cost is wood / stone / grain / iron. "Bldg" is the building level needed.

### Infantry (Barracks)

| Unit | Bldg | Cost | Train | Atk | Def | HP | Spd | Upk | Slots | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Axe Levy | 1 | 30/10/25/15 | 45 s | 25 | 15 | 130 | 5 | 1 | 1 | Cheap, quick, soon spent |
| Warrior | 1 | 40/20/35/35 | 65 s | 31 | 30 | 235 | 5 | 1 | 1 |  |
| Spearman | 1 | 35/20/30/30 | 60 s | 20 | 40 | 285 | 5 | 1 | 1 | Holds walls, stops riders |
| Ambusher | 1 | 40/15/35/40 | 75 s | 40 | 20 | 190 | 6 | 1 | 1 | ×1.5 archers, ×1.2 cavalry |
| Axeman | 2 | 45/25/35/50 | 80 s | 49 | 25 | 245 | 5 | 1 | 1 |  |
| Horse Cutter | 3 | 40/25/35/45 | 80 s | 41 | 30 | 315 | 5 | 1 | 1 | ×2 cavalry |
| Warrior of Perun | 4 | 70/40/60/80 | 140 s | 80 | 45 | 445 | 5 | 2 | 2 |  |
| Axe Warrior | 4 | 75/35/60/90 | 150 s | 100 | 35 | 400 | 5 | 2 | 2 |  |
| Follower of Veles | 5 | 60/60/70/60 | 150 s | 65 | 65 | 635 | 5 | 2 | 2 |  |
| Horse Butcher | 5 | 60/40/60/80 | 150 s | 80 | 45 | 550 | 5 | 2 | 2 | ×2.2 cavalry |
| Battering Ram | 5 | 300/40/80/140 | 380 s | 25 | 70 | 360 | 3 | 3 | 2 | Siege engine; breaches stronghold walls |
| Large Shield | 6 | 80/60/50/70 | 160 s | 47 | 90 | 1115 | 4 | 2 | 2 |  |
| Noble Spearman | 6 | 70/50/60/90 | 170 s | 75 | 75 | 830 | 5 | 2 | 2 | ×1.8 cavalry |
| Champion of Perun | 7 | 140/90/120/180 | 300 s | 225 | 70 | 970 | 5 | 3 | 3 |  |
| Perun's Axe | 8 | 150/80/120/200 | 320 s | 355 | 55 | 1090 | 5 | 3 | 3 |  |
| Veles' Chosen | 8 | 130/120/130/150 | 320 s | 195 | 100 | 1380 | 5 | 3 | 3 |  |
| Chosen Shield | 9 | 150/140/120/180 | 360 s | 165 | 140 | 2385 | 4 | 3 | 3 | ×1.8 cavalry |
| Warlord's Guard | 9 | 180/140/160/240 | 400 s | 350 | 100 | 1750 | 5 | 4 | 3 |  |

### Archers (Shooting Range)

| Unit | Bldg | Cost | Train | Atk | Def | HP | Spd | Upk | Slots | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Archer | 1 | 50/15/30/40 | 75 s | 35 | 20 | 165 | 5 | 1 | 1 |  |
| Skirmisher | 2 | 40/15/30/40 | 70 s | 30 | 25 | 200 | 6 | 1 | 1 | ×1.5 infantry, ×1.2 cavalry |
| Poison Archer | 3 | 50/15/35/50 | 90 s | 49 | 15 | 215 | 5 | 1 | 1 | **Poisons**; ×1.8 infantry, ×1.4 cavalry |
| Hunter | 4 | 80/25/50/60 | 130 s | 70 | 30 | 300 | 6 | 1 | 2 |  |
| Scorpion | 4 | 220/60/70/160 | 360 s | 70 | 25 | 150 | 3 | 3 | 2 | Siege engine; ×2 cavalry, ×1.1 infantry |
| Noble Skirmisher | 5 | 80/40/60/80 | 150 s | 80 | 40 | 445 | 7 | 2 | 2 | ×1.5 infantry, ×1.3 cavalry |
| Poison Hunter | 5 | 90/30/60/80 | 160 s | 100 | 25 | 395 | 6 | 2 | 2 | **Poisons**; ×1.9 infantry, ×1.5 cavalry |
| Onager | 6 | 250/200/80/120 | 400 s | 90 | 20 | 165 | 3 | 3 | 2 | Siege engine; ×1.8 infantry, ×1.2 archers |
| Devana's Hunter | 7 | 130/50/100/140 | 280 s | 195 | 45 | 665 | 7 | 2 | 3 | ×1.5 infantry, ×1.3 cavalry |
| Perun's Thunder Thrower | 9 | 200/120/150/260 | 450 s | 140 | 40 | 285 | 4 | 4 | 2 | Siege engine; ×1.6 inf, ×1.4 cav, ×1.2 archers |

### Cavalry (Stables)

| Unit | Bldg | Cost | Train | Atk | Def | HP | Spd | Upk | Slots | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Horse Raider | 1 | 40/30/60/80 | 120 s | 45 | 25 | 200 | 10 | 2 | 1 | Carries 80 |
| Raider | 2 | 35/20/50/50 | 90 s | 42 | 15 | 155 | 12 | 1 | 1 | Carries 120 |
| Military Caravan | 2 | 120/20/40/30 | 150 s | 0 | 60 | 450 | 5 | 0.5 | 1 | Support (wagon): +200 grain for its army; carries 400 loot |
| Horse Archer | 4 | 70/30/80/90 | 180 s | 75 | 30 | 310 | 11 | 2 | 2 | ×1.5 archers, ×1.3 infantry |
| Large Military Caravan | 4 | 260/40/80/70 | 300 s | 0 | 80 | 600 | 7 | 1 | 1 | Support (wagon): +300 grain; carries 1 engine or 10 foot soldiers; carries 600 loot |
| Bear Rider | 6 | 80/60/160/140 | 300 s | 115 | 70 | 555 | 7 | 4 | 2 | ×1.5 archers, ×1.2 infantry |
| Svarog's Raider | 8 | 150/90/180/260 | 420 s | 250 | 80 | 860 | 11 | 4 | 3 |  |

### Scouts (Scout Lodge)

| Unit | Bldg | Cost | Train | Spd | Stealth | Intel | Notes |
|---|---|---|---|---|---|---|---|
| Scout | 1 | 30/20/20/10 | 45 s | 12 | 1 | 1 | |
| Pathfinder | 3 | 70/40/50/40 | 120 s | 16 | 0.5 | 2 | Eases harsh terrain for its army (5% each, at most 50%) |
| Assassin | 6 | 150/80/100/160 | 360 s | 14 | 0.35 | 3 | 10% each to kill a horde's leader |

Lower **stealth** is better: it scales the chance of being caught
([page 12](12-scouting-and-expansion.md#scouting-a-horde)).

### Others

| Unit | Building | Cost | Notes |
|---|---|---|---|
| Shaman | Hospital 2 | 40/20/80/20 | **Support (healer):** never fights; each gives every fallen soldier of its side a 5% chance to get up again, at most 50% |
| Settler | Settlers' Lodge 1 | 300/250/300/150 | Founds villages (3 per village); trains one at a time; costs ×1.5 for every 3 bought |

### Clan units

Only members of that clan can train these ([page 10](10-heroes-generals-clans.md#clans)):

| Unit | Clan | Bldg | Atk | Def | HP | Spd | Slots | Notes |
|---|---|---|---|---|---|---|---|---|
| Forest Archer | Rys (Lynx) | Range 2 | 47 | 28 | 230 | 6 | 1 |  |
| River Barge | Bobr (Beaver) | Barracks 2 | 30 | 45 | 625 | 7 | 1 | Carries 200 |
| Border Rider | Sokol (Falcon) | Stables 3 | 55 | 32 | 260 | 14 | 1 |  |
| Aurochs Guard | Tur (Aurochs) | Barracks 2 | 29 | 62 | 410 | 4 | 1 |  |
| Raven Javelineer | Gavran (Raven) | Range 2 | 48 | 24 | 210 | 7 | 1 |  |
| Fox Rider | Lisica (Fox) | Stables 3 | 50 | 28 | 260 | 13 | 1 | Carries 120 |
| Serpent Axeman | Zmija (Serpent) | Barracks 3 | 60 | 30 | 340 | 5 | 1 |  |

## Training

- **Batches.** A village trains in batches of up to 50 units. It keeps up to
  3 batches waiting, plus 1 for every 5 levels of *each* of its Barracks,
  Shooting Range and Stables.
- **Training speed.** A unit's time shrinks ×0.9 for every level of its
  building above the first level it can be trained at, then by `trainTime`
  bonuses and world speed:
  - **Research:** Drill Yards −10%, Svarog's Forge −10%, Svarog's Living
    Flame −15%.
  - **The Shrine** of Svarog −3% a level.
  - **Longhouse Hall** −2% a level.
  - **Per unit:** Nastasya trains Spearmen 15% faster; Medvěd trains settlers
    50% slower.
- **Paying.** A batch is paid when queued.
- **Cancelling.** A batch not yet finished can be cancelled: those already
  trained stay, and the rest are paid back in full.

### Army slots

Every unit takes **army slots** (the Slots column above), and a player's
villages give only so many:

| | Slots |
|---|---|
| Units needing a building below level 4 | 1 |
| Units needing level 4 to 6 | 2 |
| Units needing level 7 or more | 3 |
| Siege engines | 2 |
| Wagons and Shamans | 1 |
| Scouts and settlers | 0 |

- **What a player has.** Each of their standing villages gives **30**, plus
  **10** for each Elder's Hall level. A village at Hall 10 gives 130.
- **What counts.** All the player's garrisons and troops in training, their
  armies out on the map and their caravans' escorts.
- **Full.** No more units are trained once the slots are full. Troops
  already there stay (a razed village's slots are gone, but not its
  armies).
- **Why.** Stronger troops do more per slot. Counting the building levels
  they need at a fiftieth of their cost, each unit fights about as well per
  resource spent as its family's first unit (Axe Levy, Archer, Horse
  Raider), but takes far fewer slots for its strength. Cheap troops are the
  quick answer early; a full army of them is the weakest one late.

### Settlers

- **One at a time.** Settlers train one at a time, and not while another is in
  training in that village.
- **Rising price.** For every 3 a player has bought, the next ones cost ×1.5
  (each priced as it is queued).
- **Getting a refund.** A cancelled settler is paid back at the dearest price.
  A settler who falls in battle makes the next ones cheaper again.

## Special units

### Healers

- **What they do.** Each Shaman gives every soldier of its side who falls a 5%
  chance to get up again, up to 50%.
- **In an army,** this works for every round it fights, but not when it
  starves.
- **In a garrison,** it adds to the Hospital's 5% a level when the village
  holds.

### Wagons and transports

- **Not soldiers.** Military caravans are wagons, support units: they don't
  fight and aren't struck. They carry extra grain for their army (200 or 300)
  and the most loot of any unit (400 and 600).
- **Wagon fort.** On open ground they can be drawn into a wagon fort
  ([page 8](08-armies-and-field.md#wagon-fort)). Only then do they fight: as
  a **wall before the army's archers**. While any wagon stands, the blows aimed
  at the archers fall on the wagons instead. That's why they're tough: 60
  defense and 450 health for a Military Caravan, 80 and 600 for a large one.
- **Transport.** A Large Military Caravan carries, per wagon, either 1 siege
  engine (loaded first) or 10 foot soldiers, the slowest first. Those riding
  move at the wagon's pace (7) and don't set the army's speed.

### Siege engines

- **Battering Ram:** takes a quarter of a stronghold's walls off its
  defenders, in raids and in strikes on horde encampments
  ([page 13](13-events-and-raids.md)).
- **Scorpion:** drives bolts through riders (×2 against cavalry).
- **Onager and Thunder Thrower:** heavy throwers.
- **Speed.** All engines are slow (2–4) and carry little food.

### Support units

Scouts, healers (the Shaman) and wagons (military caravans) are **support
units**:

- **Never fighting.** They stand aside in every battle, aren't struck, and
  ride home with their army. The one exception is wagons in a wagon fort,
  above.
- **What they still do.** Healers still heal and scouts still give intel.
- **Riding home.** An army left with only support units, every soldier fallen,
  rides home.

### Scouts in armies
- **Intel.** Each point of their intel makes the army fight 2% better in
  attack and defense, at most +10% ([page 12](12-scouting-and-expansion.md#scouts-with-an-army)).

## Forging and afflictions

The **Blacksmith** improves a unit's attack, defense, health and speed
(3 levels of +10%) and can add fire arrows or poisoned blades
([page 11](11-research-faith-smithing.md#the-blacksmith)). Poison Archers and
Poison Hunters poison without it. How burn and poison work in battle is on
[page 6](06-battles.md#burn-and-poison).
