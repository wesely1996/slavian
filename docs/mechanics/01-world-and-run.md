# 1. The world and the run

[← Index](README.md) · Next: [Map, movement and terrain →](02-map-and-movement.md)

## The goal

Slavian is cooperative and has no player-versus-player. A group of 1 to 6
players founds villages around the **Holy City**, the last bastion of the old
faith, and holds off hordes that come from the edges of the map every day.

- **The group wins** by raising all five stages of the **Kalinov Bridge** in
  the Holy City and then surviving **Ritual Night**, when every front attacks
  at once ([page 14](14-bridge-and-endgame.md)).
- **The group loses** when the Holy City's **Sanctity** falls to 0.

A world is one **run**: one map, one seed, one group, one difficulty. It ends
in a win or a loss, and the next run is a new world. A run is meant to last
about six weeks at speed 1.

A player is never knocked out. Villages can burn, but a player left with only
ruins gets a **refugee camp** near the Holy City ([page 9](09-hordes-and-threats.md#raid-or-raze)).

## The Holy City and Sanctity

The Holy City stands at the centre of the map, `(0, 0)`.

| | |
|---|---|
| Sanctity at the start | 100 |
| Its own guard | 20 Spearmen and 10 Archers, growing ×1.057 every wave |
| The guard's stance | Defensive |
| Damage from a horde that wins there | By what survives, by each soldier's tier ([below](#sanctity-damage)) |
| Rebuilding | Impossible: a fallen Holy City ends the run |

- Every horde counts the Holy City as a possible target, as if it were the
  nearest settlement on its road ([page 9](09-hordes-and-threats.md#choosing-a-target)).
- The Holy City holds the group's shared **vault** ([page 4](04-economy-and-logistics.md#the-holy-city-vault))
  and the **Kalinov Bridge**.
- Armies of any player can stand there and fight its battles.

### Sanctity damage

A horde that beats the Holy City's defenders takes Sanctity for every soldier
still standing, by tier ([page 9](09-hordes-and-threats.md#enemy-units)):

| Survivor | Sanctity each |
|---|---|
| Tier 1 | 0.5 |
| Tier 2 | 1 |
| Tier 3 | 1.5 |
| Tier 4 | 2.5 |
| Siege engine (no tier) | 0.5 |
| The Avatar of Černobog | 100: the whole of it |
| The Leshen | 50 |

The total is rounded up. Example: 4 tier-1 and 2 tier-3 survivors take
4 × 0.5 + 2 × 1.5 = 5 Sanctity.

## The map

- **Grid.** Pointy-top hexes in axial coordinates, the Holy City at `(0, 0)`.
- **Starts.** Players begin on the ring 2 hexes from the centre, spread
  evenly around it.
- **Radius.** It grows with the number of players:

| Players | Map radius |
|---|---|
| 1–2 | 10 |
| 3 | 12 (rounded from 11.5) |
| 4 | 13 |
| 5 | 15 (rounded from 14.5) |
| 6 | 16 |

- **Edge belt.** The outer rings are the unsettleable *edge belt*: ocean,
  dark forest, ice, steppe and the hallowed lands. Hordes come out of it.
- **The enemy lands.** Past the belt, behind each active front, its own
  lands run 10 rings further, four bands deep
  ([page 18](18-enemy-lands.md)).
- **Inside the belt.** Plains, forest, hills, wooded hills, swamp, lakes,
  mountains and rivers ([page 2](02-map-and-movement.md)). Woods cover about
  a fifth of the inner map and hills about an eighth.
- **Ancient sites.** At least 5 per world, 3 per player, mostly in the
  borderlands ([page 12](12-scouting-and-expansion.md#ancient-sites)).

## Fronts

The four sides of the map are the **fronts** hordes come from. How many are
active depends on the group's size:

| Group | Active fronts |
|---|---|
| Solo | North and South |
| 2 players | North, South and East |
| 3–6 players | All four: North, East, South, West |

| Front | Faction | Character |
|---|---|---|
| North | Monsters of the North | Beasts from Slavic folklore. Erratic targets, fight on past reason, never build siege engines, keep off roads |
| East | Nomad Horde | Fast horse archers. Raid rather than raze, carry off half again as much, burn outposts up to 2 hexes from their road |
| South | Order of the One Throne | Disciplined zealots with crossbows. Slow, hard to break, build siege rams |
| West | Order of the One Throne (western host) | Knights and crossbows. Build siege towers |

The Order is a fictional faction, not a real church. The factions and their
units are listed on [page 9](09-hordes-and-threats.md#fronts-and-factions).

## Difficulty: the five titles

The difficulty is chosen when a world is created. Each title is a
hereditary rank, easiest first:

| Title | Wave scale | Floor | Max factor | Power weight | Camps | Fear weight | Raze threshold | Raid-only waves |
|---|---|---|---|---|---|---|---|---|
| Baron | ×1.1 | 0.8 | 2 | 0.5 | ×1 | ×1 | +0 | 5 |
| Viscount | ×1.25 | 1.0 | 2.5 | 0.75 | ×1.5 | ×1.25 | −0.5 | 3 |
| Count | ×1.5 | 1.2 | 3 | 1.0 | ×2 | ×1.5 | −1 | 0 |
| Marquess | ×1.75 | 1.4 | 3.5 | 1.25 | ×2.5 | ×1.75 | −1.5 | 0 |
| Duke | ×2.0 | 1.6 | 4 | 1.5 | ×3 | ×2 | −2 | 0 |

- **Wave scale, floor and max factor** set how big each wave is, together
  with the group's strength. See [wave size](09-hordes-and-threats.md#wave-size).
- **Power weight** sets how strongly hordes grow with the group: with every
  village beyond one per player, and with every army stronger than expected.
- **Camps** multiplies how many bandit camps rise after each wave.
- **Fear weight** multiplies how much hordes avoid places where they were
  beaten.
- **Raze threshold** is added to the raze decision. Lower means hordes burn
  villages sooner.
- **Raid-only waves** is the grace: during these first waves, hordes only
  plunder and never raze.

Winning a run earns that title's achievement, from *Baron of the Bridge* to
*Duke of the Bridge* ([page 14](14-bridge-and-endgame.md#achievements)).

## World speed

- **What it does.** Speed divides every game-hour duration (building,
  training, marches, research, quests, fires, events). It multiplies
  production and upkeep.
- **Normal speed** is 1. Worlds can be faster, up to 100 for testing; the
  scenario tests run at 50.
- **Battle rounds** keep their 10 real minutes at any speed.

## Pacing

| | |
|---|---|
| First horde | sets out after 5 days (120 game hours) of grace |
| Afterwards | one horde a day (every 24 game hours), the fronts taking turns |
| Known ahead | the next 2 hordes are always on the schedule |
| Warning push | a horde due at your village within 6 game hours, plus 1 hour per Watchtower level |

The whole schedule is public. What a horde is made of stays hidden until it
is scouted ([page 12](12-scouting-and-expansion.md#scouting-a-horde)).

## Quiet hours

- **The window.** The group sets one daily window, in local time.
- **Hordes wait.** A horde whose march would arrive inside it stops outside
  and arrives when the window ends. No horde arrives and no battle starts
  during quiet hours.
- **Pushes wait.** Push notifications are held until the window ends.

## Solo and co-op

- **Co-op worlds** run on the server. Players join with an invite code; there
  are no public lobbies. A run already under way can still be joined.
- **Solo worlds** run on the phone with no server at all, with the same rules.
- **What only co-op has.** The Market's bounty board, chat and gifting
  between players.
- **Solo instead.** The "gift a teammate" quest becomes "fill the Holy City's
  vault".

## Getting started

Each player has a chain of six getting-started quests for the first days:

| Step | Do it once | Reward (wood/stone/grain/iron) |
|---|---|---|
| Raise a building | Queue any building or field upgrade | 300 / 300 / 200 / 100 |
| Train defenders | Build a Barracks and train any unit | 200 / 100 / 300 / 200 |
| Claim an outpost | Claim a resource hex near the village | 400 / 400 / 200 / 200 |
| Send scouts | Build a Scout Lodge and scout a horde, camp or site | 200 / 200 / 200 / 100 |
| Clear your first camp | Storm a bandit camp or lair | 600 / 600 / 600 / 400 |
| Gift a teammate | Send a caravan to a teammate or the vault (solo: to the vault) | 400 / 400 / 400 / 400 |
| Finale: every step claimed | | 800 / 800 / 800 / 500 |

- **Order.** Steps can be done in any order. Each reward waits on the quest
  card until claimed, and goes to the player's first village.
- **A camp to clear.** Every village starts with a small bandit camp of 3
  units, 2–3 hexes away.
- **Skipping.** A player can skip the whole chain at once. Every unclaimed
  reward then comes at 55% of its value, and a Storehouse is raised to
  level 3 on a free slot of the first village to hold it.

## Notifications

- **Push at once.** A horde due within the warning time, a battle at your
  village, a raided outpost, an Elder's Hall level, or any building reaching
  level 5.
- **Daily digest.** Everything else waits for it, at the player's chosen hour.
- **Expiry.** A push not delivered within 24 real hours is dropped.
- **Topics.** Players can turn pushes off by topic: hordes, battles,
  outposts, buildings, world news, digest.
