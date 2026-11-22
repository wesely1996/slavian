# Slavian game mechanics

How the game works, rule by rule: what every building, unit, horde and event
does, with the numbers the game uses. Each page covers one part of the game
and links to the others where they meet.

The numbers come from the game data in [`data/`](../../data) (each file's
`_comment` states its rules) and from the server's simulation in
[`server/src/sim/`](../../server/src/sim). The solo engine on the phone plays
by the same rules. When a number here and the data disagree, the data wins:
balance changes land there first.

## Pages

| # | Page | What it covers |
|---|---|---|
| 1 | [The world and the run](01-world-and-run.md) | The goal, the Holy City and its Sanctity, map size, fronts, difficulty titles, world speed, quiet hours, solo and co-op, the getting-started quests |
| 2 | [Map, movement and terrain](02-map-and-movement.md) | Terrain, move costs, roads and mountain passes, rivers and bridges, the river boat lanes, terraforming, fire |
| 3 | [Villages and buildings](03-villages-and-buildings.md) | Plots and slots, the Elder's Hall, build costs and times, every building, cancelling, demolishing, ruins |
| 4 | [Economy and logistics](04-economy-and-logistics.md) | Resources, production, storage, grain upkeep, outposts, the Market and bounty board, caravans, merchants, the vault, standing orders |
| 5 | [Units and training](05-units-and-training.md) | Unit families and tiers, the full unit list, training queues and speed, army slots, special units (healers, wagons, siege engines, scouts, settlers) |
| 6 | [Battles](06-battles.md) | Rounds, the damage formula, terrain, stances, counters, matchups, breaking, champions, burn and poison, loot |
| 7 | [Walls and sieges](07-walls-and-sieges.md) | Wall tiers, towers, manning, escalade, siege engines, volley rounds, breaching, charging out, the hospital |
| 8 | [Armies in the field](08-armies-and-field.md) | Armies on the map, orders, grain and quarters, attrition, reinforcements (pincer, hammer, harassment), field setups, forts, supply points, wagon forts |
| 9 | [Hordes and threats](09-hordes-and-threats.md) | Fronts and factions, the wave schedule, wave size, enemy tiers, the horde AI, fear, raiding and razing, enemy leaders, hatred, camps and lairs |
| 10 | [Heroes, generals and clans](10-heroes-generals-clans.md) | The hero roster, skills, gear, wounds, quests and army quests, generals, the ten clans |
| 11 | [Research, faith and the Blacksmith](11-research-faith-smithing.md) | Shared research, lore scrolls, Svarog's Embers, the Shrine and its gods, the Blacksmith's forging |
| 12 | [Scouting, exploration and expansion](12-scouting-and-expansion.md) | Scouts and reports, assassins, ruin searches, ancient sites, outposts, founding villages |
| 13 | [Events and raids beyond the edge](13-events-and-raids.md) | Daily map events (captives, ruins, shipyards, the cultist ritual, the mountain city), raids into enemy lands, strikes on gathering hordes, expeditions from the field |
| 14 | [The Kalinov Bridge and the endgame](14-bridge-and-endgame.md) | The five bridge stages, their quests, construction raids, Ritual Night, winning and losing, achievements |
| 15 | [Player against player](15-player-vs-player.md) | PvP worlds: protection, attacking and razing other players' villages, the fight, rivals |
| 16 | [Battle lines and maneuvers](16-battle-lines.md) | The line's width, the opening volley, flank, pincer, encirclement, breakthrough, Shield Bearer, bridges, roads and forts |
| 17 | [Forts](17-forts.md) | A fort's Keep, Storage, Fort Garrison, wall rings and towers, its defenders, ring-by-ring sieges, the zone of influence, grain upkeep and bandit takeover, sharing a hex, the rally point, tearing down |

## Reading the numbers

- **Game hours vs real time.** Most durations are *game hours*: the world's
  speed divides them. In a world at speed 2 a "6 game hour" fire burns 3 real
  hours. Production and upkeep are multiplied by world speed in the same way.
  The one exception is a **battle round, always 10 real minutes**, so
  reinforcements have time to arrive.
- **Bonuses add up.** Research, lore scrolls, clan, hero, gear, generals, the
  Shrine, bridge blessings, buildings and the Blacksmith all write into the
  same set of bonus keys (`attack.infantry`, `production.grain`,
  `buildTime`…). Values of the same key are added together before they are
  used, so +10% and +5% make +15%, not +15.5%.
- **"Level n costs base × growth^(n−1)."** Almost everything that has levels
  grows this way: building costs and times, production, storage, outpost
  yields, research per hour.
- **Hexes.** The map is a hex grid with the Holy City at its centre `(0, 0)`.
  "Within 4 hexes" means a hex distance of 4 or less.
