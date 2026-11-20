# 9. Hordes and threats

[← Armies in the field](08-armies-and-field.md) · [Index](README.md) · Next: [Heroes, generals and clans →](10-heroes-generals-clans.md)

## Fronts and factions

Each front has its own faction and personality:

| | North | East | South | West |
|---|---|---|---|---|
| Faction | Monsters of the North | Nomad Horde | Order of the One Throne | Order (western host) |
| Spawns in | Dark forest, ice | Steppe | Hallowed lands | Hallowed lands |
| Greed (loot) | ×0.6 | ×1.5 | ×0.8 | ×0.8 |
| Raid reach (outposts burned) | 1 hex | 2 hexes | 1 hex | 1 hex |
| Nerve | ×1.15 | ×0.85 | ×1.25 | ×1.25 |
| Raze bias | +0.5 | −2.5 | +1 | +1 |
| Erratic targeting | 0.6 | 0.15 | 0.05 | 0.05 |
| Siege engine | none | Scaling ladders | Siege ram | Siege tower |
| Favoured stances | Offensive | Offensive, Balanced | Hold the Line | Hold the Line, Balanced |

- **The North** keeps off roads and never builds engines.
- **The East** raids rather than razes.
- **The Order** razes readily and doesn't break easily.

### Enemy units

Each front has an infantry, an archer and a cavalry unit in each of **four
tiers**. A tier joins the hordes from wave **0, 8, 15 and 25** (counting from
0). Once a newer tier joins, every older tier is half as common for each tier
added after it, so later hordes are mostly the newest troops.

| Tier | North | East | South / West |
|---|---|---|---|
| 1 | Leshy's Thrall, Rusalka, Grey Wolf | Steppe Levy, Horse Archer, Steppe Raider | Zealot, Crossbowman, Mounted Sergeant |
| 2 | Cave Bear, **Upyr** (poisons), Volkolak | **Steppe Shaman** (poisons), Kipchak Bowman, Lancer | Inquisitor, Arbalester, Knight-Brother |
| 3 | Likho, Storm Vila, Black Boar | Kurgan Guard, **Fire Archer** (burns), Khan's Guard | Templar, Pavise Crossbowman, Grand Knight |
| 4 | Div, **Firebird** (burns), **Zmey Whelp** (burns; groups of 3+) | Bagatur, Khan's Marksman, Steppe Cataphract | Champion of the Throne, **Fire Priest** (burns), Lord Marshal |

- **Siege engines on the march.** The Order's hordes may also bring Siege Rams
  (from wave 10), Siege Towers (13) and Catapults (15), in groups of 2–3 or
  more.
- **The Avatar of Černobog** only appears through the cultist ritual
  ([page 13](13-events-and-raids.md#the-cultist-ritual)). It razes every
  village before it turns on the Holy City.
- **Tiers and the Holy City.** A horde that wins at the Holy City takes more
  Sanctity for higher-tier survivors ([page 1](01-world-and-run.md#sanctity-damage)).
- **The almanac** lists every enemy with its numbers.

## The wave schedule

| | |
|---|---|
| Grace | 5 days (120 game hours) before the first horde sets out |
| Rhythm | One horde every 24 game hours after that |
| Fronts | The active fronts take turns |
| Known ahead | The next 2 hordes, with their front, target, size class and arrival time |
| Quiet hours | A horde that would arrive inside them waits until they end |

**Threat levels** describe a horde's size before it is scouted: Low (up to
12 units), Moderate (up to 25), High (up to 50), Severe (more).

## Wave size

```
base   = 8 × 1.068^wave index × (1 + 0.5 × (players − 1))

factor = title's wave scale
         × (1 + power weight × (extra villages + extra army))
         × (1 + 0.1 × bridge stages finished)
         kept between the title's floor and max factor

size   = base × factor
```

- **Extra villages:** villages per player above one.
- **Extra army:** how much the group's total attack (every fighting unit's
  attack, summed) is above what's expected. Expected is 600 per player,
  growing 6% a wave.
- **The point.** A group that grows faster than expected faces bigger hordes,
  so it's worth staying ahead.
- **Hatred** doesn't add troops: it makes them stronger ([below](#hatred)).
- **Composition.** The size is split among the front's unlocked units by
  weight.
- **Camps join.** Every camp of the front sends half its troops along when a
  horde sets out ([below](#camps-and-lairs)).

## Choosing a target

A horde goes for the **nearest settlement** by road, with costs that steer it:

- **Fear:** places where hordes were beaten ([below](#fear)).
- **The Holy City** is always a target, counted like the nearest settlement:
  it is struck when no village is closer, and a tie goes to the village.
- **Erratic fronts** jitter their costs: monsters choose wildly.

Once it reaches its first target, the horde's **rampage clock** starts:
**18 game hours**. Until the clock runs out it moves on to the next village it
hasn't hit. Then it settles into a bandit camp. A horde also ends when wiped
out, or when it reaches the Holy City.

**On the road,** a marching horde burns every outpost within its raid reach
of its road down one level, and burns supply points nobody stands on.

## Fear

- **Building it up.** A horde beaten at a hex leaves fear there: 10, plus 0.2
  for every soldier it lost.
- **Fading.** Fear shrinks to 81.5% of itself every time a wave spawns, and is
  forgotten below 0.5.
- **Its effect.** Hordes add fear × 1 to a target's cost, and fear × 0.5 to
  every feared hex they would cross. The difficulty's fear weight multiplies
  both.

**Holding a place well therefore turns hordes elsewhere,** onto a teammate or
the Holy City.

## Raid or raze

A horde that beats a village either **raids** it (plunders) or **razes** it
(burns it to a ruin):

- **Grace.** During the title's first raid-only waves (Baron 5, Viscount 3,
  higher titles 0), hordes only raid.
- **Razing needs time:** at least 3 game hours of rampage left.
- **Razing needs strength:** at least 1.5× the help that could still come.
- **Razing needs the will.** Its front's raze bias + log₂(its strength) −
  (1 if it is under half its first numbers) must reach the threshold of 1,
  shifted by the title's raze threshold.
- **Otherwise it raids:** it carries off up to 30% of the stores, less the
  more of it fell ([page 6](06-battles.md#what-victory-brings)). A raid also
  recruits 10% of its starting strength.
- **The Avatar of Černobog** always razes ([page 13](13-events-and-raids.md#the-cultist-ritual)).

**Ruins** rebuild at 40% of what stood, over 6 game hours. A player with
nothing but ruins gets a **refugee camp**, which hordes raid but never raze
([page 3](03-villages-and-buildings.md#ruins-and-rebuilding)).

## Enemy leaders

Every front has one named **leader** at a time, who leads its hordes.

- **Ranks.** It rises through ranks with its level, up to level 15. For
  example, Beg Konchak becomes Khan Konchak at level 5 and Great Khan at 10.
- **Gaining XP:** 4 per battle, 14 per win, 18 per raze, 0.25 per kill, 6 for
  escaping. Level L needs 20 × 1.4^(L−1) more.
- **Skills.** One per level after the first, in its front's order:

| Skill | Per rank | Max |
|---|---|---|
| Savagery | +4% attack for the horde | 5 |
| Thick Hide | +4% defense | 5 |
| Dread | +6% nerve (holds longer before breaking) | 4 |
| Greed | +12% carried off from a raid | 4 |

- **Beaten,** it is wounded for 30 game hours and comes back with a
  **grudge** against the village that beat it: +15% attack there.
- **Killed** (its horde wiped out, or by assassins), it is replaced by a
  rival who starts at level 1 + a third of the fallen leader's level.

## Hatred

Hatred belongs to a **front**, not to one horde. It grows, with no limit, for:

| Cause | Hatred |
|---|---|
| A hero's ambush quest delaying the front's next horde | +0.1 |
| A harassing strike on one of its hordes | +0.05 |
| A raid battle won on its side | +0.05 (+0.15 for sacking its stronghold) |
| A strike on its gathering horde | +0.6 |
| A map event left undone on its land | +0.2 |
| One of its camps or lairs burnt by fire | +0.2 |

- **Spending it.** The front's next horde to set out **takes all of it**, as a
  share added to its attack and defense, and the front's hatred starts again
  from 0.
- **More camps.** When that horde is over, hatred × 1 more camps of its front
  rise near its road, on top of the usual ones and beyond the cap. At 1.5,
  that is one camp, and a second one half the time.
- **Bands.** Each time a front's hatred passes another whole 100%, its next
  horde sends out a **band** of 10% of its troops (at least one). The band is
  a small horde of its own that marches on the nearest player village other
  than the one the main horde is after. A band leaves no camps behind.

## Camps and lairs

Bandit camps (human fronts) and monster lairs (the North) rise on the map.

- **When.** When a wave ends, 1 camp of its front rises near its road
  (×the title's camp rate), within 1 hex of the road and at least 3 hexes from
  any village. There are at most 4 per front, more through hatred.
- **Size.** It starts with 6 × 1.057^wave index units of its front, and grows
  10% every 24 game hours, up to 150.
- **Feeding hordes.** When a horde of its front sets out, every camp sends half
  its units with it.
- **Ambushes.** Caravans passing within 1 hex are ambushed
  ([page 4](04-economy-and-logistics.md#caravans)).
- **Abandoned forts** become camps of 8 ([page 8](08-armies-and-field.md#forts)).
- **Starter camps.** Every village gets a small one of 3 at the start of the
  run, 2–3 hexes away.

**Clearing a camp:**
- **The fight.** An army with orders *clear* storms it on arrival. The fight is
  resolved round by round at once, with the camp fighting from behind its
  palisade (home bonus, defensive stance).
- **Loot.** 15 wood, 15 stone, 15 grain and 8 iron per camp unit, carried home.
- **For the hero** leading it, a 35% chance of gear.
- **Lairs** also give a 75% chance of a **Svarog's Ember**.
- **Burning it.** Fire can be set on a camp in forest or wooded hills, or
  spread onto one ([page 2](02-map-and-movement.md#fire)). The camp is gone,
  but 50–100% of its troops flee at once as a small horde on the nearest
  player village, and its front's hatred rises by +0.2. The fleeing horde
  waits out quiet hours like any other, leaves no new camps behind when it
  is over, and settles into a camp again if its rampage runs out.

## Bridge construction raids

While a bridge stage is being raised, every active front sends one small
horde at a different target, with 5 + 2 × the stage's number units: the
group's villages first, then the Holy City ([page 14](14-bridge-and-endgame.md#while-a-stage-is-raised)).
