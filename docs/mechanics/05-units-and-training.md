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

| Unit | Bldg | Cost | Train | Atk | Def | HP | Spd | Upk | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Axe Levy | 1 | 30/10/25/15 | 45 s | 25 | 15 | 130 | 5 | 1 | Cheap, quick, soon spent |
| Warrior | 1 | 40/20/35/35 | 65 s | 30 | 30 | 230 | 5 | 1 | |
| Spearman | 1 | 35/20/30/30 | 60 s | 20 | 40 | 285 | 5 | 1 | Holds walls, stops riders |
| Ambusher | 1 | 40/15/35/40 | 75 s | 35 | 20 | 165 | 6 | 1 | ×1.5 archers, ×1.2 cavalry |
| Axeman | 2 | 45/25/35/50 | 80 s | 40 | 25 | 200 | 5 | 1 | |
| Horse Cutter | 3 | 40/25/35/45 | 80 s | 30 | 30 | 230 | 5 | 1 | ×2 cavalry |
| Warrior of Perun | 4 | 70/40/60/80 | 140 s | 55 | 45 | 310 | 5 | 2 | |
| Axe Warrior | 4 | 75/35/60/90 | 150 s | 65 | 35 | 260 | 5 | 2 | |
| Follower of Veles | 5 | 60/60/70/60 | 150 s | 40 | 65 | 395 | 5 | 2 | |
| Horse Butcher | 5 | 60/40/60/80 | 150 s | 45 | 45 | 310 | 5 | 2 | ×2.2 cavalry |
| Battering Ram | 5 | 300/40/80/140 | 380 s | 25 | 70 | 360 | 3 | 3 | Siege engine; breaches stronghold walls |
| Large Shield | 6 | 80/60/50/70 | 160 s | 20 | 90 | 475 | 4 | 2 | |
| Noble Spearman | 6 | 70/50/60/90 | 170 s | 40 | 75 | 430 | 5 | 2 | ×1.8 cavalry |
| Champion of Perun | 7 | 140/90/120/180 | 300 s | 95 | 70 | 410 | 5 | 3 | |
| Perun's Axe | 8 | 150/80/120/200 | 320 s | 115 | 55 | 355 | 5 | 3 | |
| Veles' Chosen | 8 | 130/120/130/150 | 320 s | 70 | 100 | 500 | 5 | 3 | |
| Chosen Shield | 9 | 150/140/120/180 | 360 s | 40 | 140 | 585 | 4 | 3 | ×1.8 cavalry |
| Warlord's Guard | 9 | 180/140/160/240 | 400 s | 100 | 100 | 500 | 5 | 4 | |

### Archers (Shooting Range)

| Unit | Bldg | Cost | Train | Atk | Def | HP | Spd | Upk | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Archer | 1 | 50/15/30/40 | 75 s | 35 | 20 | 165 | 5 | 1 | |
| Skirmisher | 2 | 40/15/30/40 | 70 s | 30 | 25 | 200 | 6 | 1 | ×1.5 infantry, ×1.2 cavalry |
| Poison Archer | 3 | 50/15/35/50 | 90 s | 30 | 15 | 130 | 5 | 1 | **Poisons**; ×1.8 infantry, ×1.4 cavalry |
| Hunter | 4 | 80/25/50/60 | 130 s | 55 | 30 | 230 | 6 | 1 | |
| Scorpion | 4 | 220/60/70/160 | 360 s | 70 | 25 | 150 | 3 | 3 | Siege engine; ×2 cavalry, ×1.1 infantry |
| Noble Skirmisher | 5 | 80/40/60/80 | 150 s | 50 | 40 | 285 | 7 | 2 | ×1.5 infantry, ×1.3 cavalry |
| Poison Hunter | 5 | 90/30/60/80 | 160 s | 50 | 25 | 200 | 6 | 2 | **Poisons**; ×1.9 infantry, ×1.5 cavalry |
| Onager | 6 | 250/200/80/120 | 400 s | 90 | 20 | 165 | 3 | 3 | Siege engine; ×1.8 infantry, ×1.2 archers |
| Devana's Hunter | 7 | 130/50/100/140 | 280 s | 90 | 45 | 310 | 7 | 2 | ×1.5 infantry, ×1.3 cavalry |
| Perun's Thunder Thrower | 9 | 200/120/150/260 | 450 s | 140 | 40 | 285 | 4 | 4 | Siege engine; ×1.6 inf, ×1.4 cav, ×1.2 archers |

### Cavalry (Stables)

| Unit | Bldg | Cost | Train | Atk | Def | HP | Spd | Upk | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Horse Raider | 1 | 40/30/60/80 | 120 s | 45 | 25 | 200 | 10 | 2 | Carries 80 |
| Raider | 2 | 35/20/50/50 | 90 s | 35 | 15 | 130 | 12 | 1 | Carries 120 |
| Military Caravan | 2 | 120/20/40/30 | 150 s | 2 | 10 | 90 | 5 | 0.5 | Wagon: +200 grain for its army |
| Horse Archer | 4 | 70/30/80/90 | 180 s | 55 | 30 | 230 | 11 | 2 | ×1.5 archers, ×1.3 infantry |
| Large Military Caravan | 4 | 260/40/80/70 | 300 s | 2 | 12 | 105 | 7 | 1 | Wagon: +300 grain; carries 1 engine or 10 foot soldiers |
| Bear Rider | 6 | 80/60/160/140 | 300 s | 85 | 70 | 410 | 7 | 4 | ×1.5 archers, ×1.2 infantry |
| Svarog's Raider | 8 | 150/90/180/260 | 420 s | 130 | 80 | 445 | 11 | 4 | |

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
| Shaman | Hospital 2 | 40/20/80/20 | **Healer:** each gives every fallen soldier of its side a 5% chance to get up again, at most 50% |
| Settler | Settlers' Lodge 1 | 300/250/300/150 | Founds villages (3 per village); trains one at a time; costs ×1.5 for every 3 bought |

### Clan units

Only members of that clan can train these ([page 10](10-heroes-generals-clans.md#clans)):

| Unit | Clan | Bldg | Atk | Def | HP | Spd | Notes |
|---|---|---|---|---|---|---|---|
| Forest Archer | Rys (Lynx) | Range 2 | 45 | 28 | 220 | 6 | |
| River Barge | Bobr (Beaver) | Barracks 2 | 15 | 45 | 310 | 7 | Carries 200 |
| Border Rider | Sokol (Falcon) | Stables 3 | 50 | 32 | 240 | 14 | |
| Aurochs Guard | Tur (Aurochs) | Barracks 2 | 24 | 62 | 340 | 4 | |
| Raven Javelineer | Gavran (Raven) | Range 2 | 48 | 24 | 210 | 7 | |
| Fox Rider | Lisica (Fox) | Stables 3 | 44 | 28 | 230 | 13 | Carries 120 |
| Serpent Axeman | Zmija (Serpent) | Barracks 3 | 52 | 30 | 300 | 5 | |

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

- **Not soldiers.** Military caravans are wagons. They carry extra grain for
  their army (200 or 300).
- **Wagon fort.** On open ground they can be drawn into a wagon fort
  ([page 8](08-armies-and-field.md#wagon-fort)).
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

### Scouts in armies

- **Never fight.** Scouts stand aside in battle and ride home with their army.
- **Intel.** Each point of their intel makes the army fight 2% better in
  attack and defense, at most +10% ([page 12](12-scouting-and-expansion.md#scouts-with-an-army)).

## Forging and afflictions

The **Blacksmith** improves a unit's attack, defense, health and speed
(3 levels of +10%) and can add fire arrows or poisoned blades
([page 11](11-research-faith-smithing.md#the-blacksmith)). Poison Archers and
Poison Hunters poison without it. How burn and poison work in battle is on
[page 6](06-battles.md#burn-and-poison).
