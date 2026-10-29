# Slavian — Game Design & Implementation Plan

> Working title: **Slavian**. A cooperative, PvE, hex-map strategy game for busy adults.
> Mobile-first (Android), cross-platform later. Players give orders in short check-ins; everything executes over real time on the server.

This plan is the outcome of a design interview. Each decision below is settled unless marked **(to verify)** or **(tunable)**. Numbers marked *(tunable)* are starting values that live in data files and get rebalanced.

---

## 1. Vision

The last bastion of Slavic faith and culture is the **Holy City**. A small group of friends (2–6, or solo) found villages around it, grow them, claim the land and prepare for the hordes coming from every direction. They win by extending the **Kalinov Bridge**, which already joins Nav to Yav, on from Yav to Prav before the city falls.

- **Inspirations:** Travian (village interior, real-time timers, troop marches) and Ikariam (calm economy, few-minutes-a-day loop).
- **Twist:** fully cooperative PvE. No PvP. The enemy is nature, monsters and three invading forces.
- **Core feeling:** *"We know where they will come from. Do we have enough time?"* Preparation, scouting and layered defense.
- **Respect for time:** a few minutes, several times a day. Orders queue up; the server executes them. Waves never hit during the group's quiet hours.

### Pillars
1. **Co-op over competition.** Everything shared: resources, troops, the vault, the bridge.
2. **Plan, then wait.** Decisions matter more than reflexes or online time.
3. **Readable threat.** Wave schedules are public. Compositions are earned through scouting.
4. **Setbacks, not eliminations.** Villages can burn, but a player is never out of the game.

---

## 2. Settled Decisions (summary)

| # | Topic | Decision |
|---|---|---|
| Q1 | Group | 2–6 players per world, solo allowed. Invite-code only, no public lobbies. |
| Q2 | World | Fixed-length **run** (~6 weeks target), ends in win or loss. A new world with a new seed afterwards. |
| Q3 | Time | Real wall-clock timers, server-authoritative simulation. |
| Q4 | Connectivity | Co-op worlds are online (the server). Single player runs entirely on the device, with no server calls (M5 step 24). |
| Q5 | Stack | **Godot 4** client, **Node + TypeScript + PostgreSQL** server, game rules as shared JSON data. |
| Q6 | Money | **No monetization.** A "Buy me a coffee" button and a monthly server-cost slider (surplus carries over to the next month). |
| Q7 | Team | Solo developer. First milestone is a vertical slice for 2 players. |
| Q8 | Map | Procedural hex map. Holy City at the center, player starts on the ring at distance 2. Radius scales with player count. Fog of war. Special edge tiles. |
| Q9 | Villages | **No village cap.** Travian-style **village interior view**. |
| Q10 | Resources | Wood, Stone, Grain, Iron + rare **Svarog's Ember**. Outposts claim resource tiles and can be raided. |
| Q11 | Combat | Automated, deterministic. Player levers: **tactics/stance**, field setups (ambush, fort, choke point), garrisons, reinforcements. Battles take real time. |
| Q12 | Enemy targeting | Dynamic: nearest settlement first, avoids fortifications that beat it. Ungarrisoned forts can turn into bandit camps. Garrisons reinforce unless told not to. |
| Q13 | Scouting | Public wave schedule + threat level. Composition hidden until scouted. Scouts are consumable; more scouts = more precision. |
| Q14 | Destruction | Any village can be destroyed and rebuilt at a percentage of its cost. Stored resources lost. Resources shareable, storable in the Holy City, transported with travel time. Donation to the bridge consumes resources. |
| Q15 | Co-op | Individual storage, free gifting/reinforcing, shared bridge project, soft specialization. |
| Q16 | Expansion limits | Rising settler cost, per-village upkeep, map scarcity. No hard cap. |
| Q17 | Horde AI | Nearest settlement weighted by fear. Attacks outposts within 1 hex of its route. Ends when wiped, at the Holy City, or when the rampage clock runs out (survivors become a camp). |
| Q18 | Battles | 15 min–3 h, round-based. Reinforcements join between rounds and can produce **pincer** / **hit-and-run** bonuses scaled by their size relative to the enemy. |
| Q19 | Raid vs raze | Decided by AI reasoning, not a coin flip. Different durations. Raids reinforce the horde but do less damage. Ruins rebuild at 40%. Refugee camp safety net. |
| Q20 | Logistics | Caravans (capacity + travel time, can be intercepted). Holy City vault: shared, safe until the city falls. Withdrawals take travel time. |
| Q21 | Edge belt | Unsettleable frontier: ocean, dark forest, ice, steppe, hallowed lands. Enemy spawn zones. Scouts explore **ancient sites** and borderlands for hero gear, resources and research. |
| Q22 | Tactics | Stance + field setup. Enemy stances hidden until scouted. Visible matchup table. |
| Q23 | Check-ins | Order queues limited by **order count per village** (grows with village size), standing orders, smart notifications + daily digest, teammate delegation. |
| Q24 | Clans | 6 animal-named clans in Interslavic. Duplicates allowed. Each has some (not all) of: best resource, unique unit, unique building, bonus, weakness. |
| Q25 | Heroes | One per player, picked from a roster of heroes with their own strengths, weaknesses, traits and portraits (step 21); leads one army, goes on quests (step 22), skill tree, gear from sites, wounded instead of killed. |
| Q26 | Research | Per-player tree (~30 techs) + **lore scrolls** from sites for rare techs and group boosts. |
| Q27 | Endgame | **Kalinov Bridge** in 5 stages (resources + quests). The final stage triggers **Ritual Night**: all active fronts attack at once. Survive it to win. |
| Q28 | Difficulty | Waves scale with **group power** (villages, armies, bridge progress) + player count, with floors. Presets: Story, Normal, Hard, Nightmare. |
| Q29 | Camps & lairs | **Spawn at the end of each wave**, giving a clearing window before the next. Uncleared camps reinforce the next wave on their nearest front and grow over time. Capped count. Loot on clear. |
| Q30 | The Church | A **fictional zealot order** ("the Order of the One Throne"). No real denomination, scripture or symbols. |
| Q31 | Art | Godot 2D, stylized flat illustration, Slavic ornament UI frames, muted earth palette with bright threat accents. Placeholder art early. |
| Q32 | Pacing | Week 1 grace period (camps/monsters only). Then a wave every 2–3 days. Soft deadline through escalation. World speed 1× / 2×. |
| Q33 | Quiet hours | Group-set quiet window. Waves and battle starts never land inside it. |
| Q34 | Simulation | Event scheduler, one writer per world, resources computed when read, all formulas server-side, shared JSON data. |
| Q35 | Protocol | HTTPS commands, WebSocket state updates, FCM push. Server validation + rate limits as the only anti-cheat. |
| Q36 | Accounts | Google (Play Games) + email sign-in, upgradable guest accounts, minimal personal data, GDPR basics. |
| Q37 | Hosting | One small VPS, Docker Compose + Postgres, off-site daily backups. Donation link + hand-updated cost/surplus JSON. |
| Q38 | Onboarding | Guided quest chain in the first 48 h of the run (inside the grace week) + in-game almanac. |
| Q39 | Languages | Translation support from day one. Launch in **English and Serbian (Latin script only)**. Colorblind-safe threat indicators, adjustable text size. |
| Q40 | Testing | Simulation unit tests, headless full-run bot simulator, data-driven balance, light telemetry. |
| Q41 | Roadmap | M0–M6 (see §12). |
| Q42 | Fronts per group size | 1 player: North + South. 2 players: + East. 3–6 players: all four. |

---

## 3. Glossary

| Term | Meaning |
|---|---|
| **World / Run** | One campaign instance: a map, a group, a seed, a difficulty. Ends in win or loss. |
| **Holy City** | The central city. Holds the vault and the Kalinov Bridge. If its **Sanctity** reaches 0, the run is lost. It cannot be rebuilt. |
| **Sanctity** | The Holy City's HP. Damaged by hordes that reach it. |
| **Village** | A player settlement occupying one hex, with an interior view of building slots. ("City" in casual speech means any settlement.) |
| **Outpost** | A gathering structure on a resource hex, owned by a village. Can be raided. |
| **Ruin** | What a razed village leaves behind. Can be rebuilt. |
| **Refugee camp** | A free minimal village next to the Holy City given to a player who has lost all villages. |
| **Front** | An enemy direction: North (monsters), South and West (the Order), East (nomads). |
| **Spawn zone** | The edge-belt area a front's hordes come from. |
| **Horde / Wave** | A scheduled enemy army from a front. |
| **Fear** | A per-location score the horde AI uses to avoid fortifications that beat it. Decays over waves. |
| **Rampage clock** | How long a horde can roam before it settles into a bandit camp. |
| **Bandit camp / Lair** | Hostile map structures (human / monster) that reinforce the next wave if uncleared. |
| **Ancient site** | Explorable map location yielding gear, resources, lore scrolls. |
| **Stance** | An army's combat posture: Defensive, Balanced, Offensive, Hold the Line. |
| **Field setup** | A prepared position on a tile: Ambush, Fort, Choke Point. |
| **Caravan** | A resource transport with capacity and travel time. |
| **Vault** | Shared storage in the Holy City. |
| **Kalinov Bridge** | The win objective: a 5-stage project in the Holy City. The mythic bridge over the Smorodina river already joins Nav (the other realm) to Yav (the living world); the group extends it from Yav to Prav (the realm of the gods), and once it reaches Prav nothing from Nav can cross it. |
| **Ritual Night** | The final event: all active fronts attack at once. |
| **Quiet hours** | The group's daily window in which no waves or battle starts happen. |
| **Standing order** | A rule that repeats or triggers automatically (repeat training, auto-rebuild, reinforcement rules). |
| **Delegation** | Temporary permission for a teammate to issue orders on your behalf. |
| **Clan (Rod)** | The player's chosen Slavic clan, giving perks. |

---

## 4. World & Map

### 4.1 Layout
- **Hex grid** with axial coordinates (pointy-top). The Holy City sits at `(0,0)`.
- **Starting ring:** distance 2 from the center (12 hexes). Players are spread evenly around it.
- **Radius** *(tunable)*: ~10 for 1–2 players, scaling up to ~16 for 6.
- **Fog of war:** hexes are revealed by village/outpost vision, armies and scouts. Revealed terrain stays known, but enemy positions are only live while in vision.

### 4.2 Terrain
| Terrain | Main yield | Combat effect | Movement |
|---|---|---|---|
| Plains | Grain | Favors cavalry | Normal |
| Forest | Wood | Ambush bonus, cavalry penalty | Slow |
| Hills | Stone, Iron | Defender bonus, fort bonus | Slow |
| Mountain | Iron, Stone (rich) | Impassable except passes | — |
| Swamp | (rare herbs / scrolls) | Attacker penalty | Very slow |
| River | — (bridges and fords are choke points) | Choke point bonus | Crossing only at fords/bridges |
| Lake | Grain (fish) | — | Impassable |

### 4.3 Edge belt (unsettleable frontier)
| Edge type | Where | Role |
|---|---|---|
| **Ocean** | Any inactive edge | Impassable. Harbor outposts give fish and trade events. |
| **Dark forest** | North | Monster spawn zone. Rare materials, monster lairs. |
| **Ice** | North | Slows movement. High-risk Svarog's Ember. |
| **Steppe** | East | Nomad spawn zone. |
| **Hallowed lands** | South / West | Order of the One Throne spawn zone. |

The borderlands next to the belt hold **ancient sites** that scouts can explore.

### 4.4 Active fronts by group size (Q42)
| Players | Active fronts |
|---|---|
| 1 | North (monsters), South (Order) |
| 2 | + East (nomads) |
| 3–6 | + West (Order) — all four |

Edges of inactive fronts are generated as ordinary terrain/ocean without spawn zones.

### 4.5 Procedural generation (outline)
1. Place the Holy City and the starting ring. Make sure each start has a fair mix of resource hexes within radius 2.
2. Generate an elevation + moisture noise field, then map it to terrain.
3. Carve 1–3 rivers from the edges toward the center, with fords/bridges as natural choke points.
4. Paint the edge belt per active/inactive front.
5. Place ancient sites in the borderlands and a few mid-map ruins.
6. Validate: every start can reach the Holy City; every active front has at least one viable path to every start; resource fairness within tolerance. Otherwise reseed.

---

## 5. Economy

### 5.1 Resources
- **Wood, Stone, Grain, Iron:** basic resources from village fields and outposts.
- **Svarog's Ember:** rare. Only from ancient sites, lairs, ice/dark-forest outposts. Needed for bridge stages and top-tier defenses.
- **Grain upkeep:** troops and population eat grain. Negative grain starves troops over time (they desert, they don't die instantly).
- **Lore scrolls:** non-tradeable research items from sites (see §8).

### 5.2 Villages
- **Interior view (Travian-style):** a village screen with a center (buildings) and surrounding fields. Tap a slot to build/upgrade.
- Starting buildings *(tunable)*: Elder's Hall (main building), Granary, Storehouse, Barracks (infantry), Stables (cavalry), Shooting Range (ranged), Wall (Palisade), Marketplace/Caravan Yard, Scout Lodge, Academy, Shrine, Hero's Hall, Settlers' Lodge, Workshop. Plus clan-unique buildings.
- **Village size** (driven by Elder's Hall + population) unlocks building slots and raises the **order queue limit** (Q23).
- **Population** grows with grain surplus and housing. It is a resource the enemy can kill when a village is besieged.

### 5.3 Outposts
- Built on a resource hex within a range of the owning village *(tunable: 2–3 hexes)*.
- Production goes to the owning village.
- Hordes attack outposts within 1 hex of their route (Q17).
- While their village is under siege, connected outposts stop producing (Q18).

### 5.4 Expansion (no cap)
- **Settlers** are trained in the Settlers' Lodge. Their cost rises with each village you own *(tunable curve)*.
- **Upkeep:** each village adds grain upkeep and a minimum-garrison recommendation (an ungarrisoned village is an attractive target).
- **Scarcity:** good hexes near the center run out. Expansion outward is closer to the fronts.

### 5.5 Logistics
- **Caravans** carry resources with a capacity and travel time *(tunable speed per terrain)*.
- Caravans can be **intercepted** by hordes and bandits on their path. Escorts are possible.
- **Vault** in the Holy City: shared storage, safe until the city falls. Capacity upgraded collectively. Deposits and withdrawals travel by caravan.
- **Donation** to the bridge is an explicit action that consumes resources from the vault or an arriving caravan.

---

## 6. Military

### 6.1 Unit families
| Family | Strong vs | Weak vs |
|---|---|---|
| Infantry (spears, shields) | Cavalry | Archers |
| Archers | Infantry | Cavalry |
| Cavalry | Archers, raiders | Infantry |
| Ritual / Support (volkhvs, healers, drummers) | Buffs, monsters | Direct assault |
| Scouts | (intel only) | Everything |
| Siege-defense (crews on forts/walls) | Attackers at walls | Field battles |

Each clan modifies or adds to these (§9).

Infantry trains in the **Barracks**, archers and throwers in the **Shooting Range**, riders in the **Stables** (`data/units.json`). Each has three tiers, opened at building levels 1–3, 4–6 and 7–9; a unit may carry its own counters in place of its family's (Horse Cutters and Horse Butchers cut riders down, poisoners hit infantry and riders alike).

| | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|
| **Infantry** (Barracks) | Axe Levy, Warrior, Spearman, Axeman, Ambusher, Horse Cutter | Warrior of Perun, Axe Warrior, Follower of Veles, Horse Butcher, Large Shield, Noble Spearman | Champion of Perun, Perun's Axe, Veles' Chosen, Chosen Shield, Warlord's Guard |
| **Ranged** (Shooting Range) | Archer, Skirmisher, Poison Archer | Hunter, Noble Skirmisher, Poison Hunter, Onager | Devana's Hunter, Perun's Thunder Thrower |
| **Cavalry** (Stables) | Horse Raider, Raider | Horse Archer, Bear Rider | Svarog's Raider |

### 6.2 Stances (Q22)
| Stance | Effect *(tunable)* |
|---|---|
| **Defensive** | +defense, −damage, fewer losses, retreats early |
| **Balanced** | No modifiers |
| **Offensive** | +damage, +losses, chases fleeing enemies |
| **Hold the Line** | Never retreats, big bonus at choke points/walls, heavy losses if broken |

Enemy hordes also have stances. They are hidden until scouted. A **visible matchup table** in the almanac shows the stance-vs-stance modifiers.

### 6.3 Field setups
| Setup | Requirement | Effect |
|---|---|---|
| **Ambush** | Forest/hills/swamp tile, army in place **before** the horde arrives, preparation time | First-round surprise damage, horde can't choose stance for round 1 |
| **Fort** | Construction (resources + time) | Persistent structure, defense bonus. **Ungarrisoned forts can become bandit camps** (probability per wave). |
| **Choke Point** | River ford/bridge, mountain pass, narrow terrain | Limits how many attackers engage per round |

### 6.4 Defending inside a village
- Better odds (walls, militia from population).
- **Costs:** the population takes losses, buildings can be damaged, connected outposts stop producing until the battle ends.

### 6.5 Battle resolution (Q11, Q18)
- **Deterministic** given the inputs and a battle seed (so reports can be replayed and tested).
- A battle is a series of **rounds**. Each round is a scheduled event. Total duration is **15 min–3 h** *(tunable)*, depending on army sizes and fortification.
- Each round computes: effective attack/defense per family × counters × stance × terrain × setup × hero × research × clan, then applies casualties.
- **Retreat thresholds** depend on stance.
- **Battle reports:** readable after the fact, with a per-round summary, losses and the key modifiers ("Ambush +30%", "Pincer +18%").

### 6.6 Reinforcements
- Every army and garrison has a **reinforce toggle** (default on) and a **priority list** (default: closest battle first, editable).
- Once a battle ends, the surviving army follows its priority list to the next battle.
- Reinforcements arrive after travel time and **join at the next round**.
- **Arrival direction bonus:**
  - **Pincer:** arriving from a different side than the defenders. Bonus scaled by reinforcement size relative to the enemy.
  - **Hit-and-run harassment:** small, fast reinforcements (cavalry-heavy) that deal damage and withdraw. Bonus scaled the same way, with low losses.
- Garrisons in forts and villages join battles in range once they start, unless set not to.

### 6.7 Heroes (Q25)
- One per player. Leads one army or garrison.
- **Skill tree** with three branches (e.g. Warlord, Warden, Wayfinder) *(tunable)*.
- **Gear slots** (weapon, armor, amulet, banner, mount) from ancient sites, lairs and camps. Some items form sets.
- **Defeated = wounded** for several hours, then back. Never permanently dead.
- A **Hero's Hall** in a village heals the hero faster there (8% a level).

### 6.8 Generals
- Lesser heroes recruited at a **Hero's Hall** (`data/heroes.json`, `generals`). A player keeps one general per Hall, plus one more every two of its levels.
- They have levels (from kills) but no skills, gear or quests. Each level adds +2% attack and defense to the troops they lead.
- A general **leads an army** it marches with (beside the hero or alone), or **commands the garrison** of the village it stands in (the best one there). Generals travel between your villages.
- **Only the hero is wounded:** a general whose side loses a battle is killed.

### 6.9 Field armies and supply
- **Armies live on the map.** One that holds a hex, clears a camp, explores a site or supports a village stays there until it is moved to another hex, marched into a settlement (joining the garrison of your own village) or called home. Reinforcements and harassers still ride home by themselves, and a beaten army retreats home.
- **Garrisons** (troops at home and in training) eat half their grain upkeep. Units away on errands (scouts, settlers, caravan escorts) eat in full.
- **An army carries its own grain:** each unit marches out with its own game hours of its upkeep (`supplyHours` in `data/units.json`): heavy infantry and siege engines 16–20, line infantry and archers 22–26, light infantry and skirmishers 28–32, riders 30–44, scouts 48. It takes them from the settlement it leaves (as much as there is), eats full upkeep from it, and its home village no longer feeds it. Any village it reaches or stands in fills it up again; what is left goes into the stores of the village it joins.
- **Attrition** (`data/armies.json`): out of food, it marches 25% slower; 8 game hours later it loses 5% of each unit (rounded up) every hour; after a day without food it is lost. Its general dies, and the hero is carried home wounded.
- Soldiers can be **dismissed** from a garrison, and a standing army can be **disbanded**.
- **The army sheet:** tapping an army on the map (or *View* in a list) opens its own sheet: where it is, each kind of troop with what it eats and how long it carries food, its grain (a gauge, what it eats a game hour, how long it lasts), its **fatigue** (from hunger alone: fed, hungry and slower, starving and losing men, a gauge to the day it is lost), the store where it stands, and its orders. *Move* then a tapped hex (or village) sends it there. Forts and supply points show their grain as a gauge on the map.

- **Supply points** (`data/field.json`, `supplyPoint`) are built like forts, within 5 hexes of a village and paid from it: grain stores with no walls, keeping up to 6000 grain. **Forts keep grain too** (up to 3000).
- An army that arrives at or stands on a fort or supply point **fills up from its grain** as it would in a village: on arrival, when its own grain runs out, or when told to take on grain. A standing army there can also **leave grain** from its own supply.
- **Hordes burn supply points:** one passing within its raid reach of a supply point (built or being built) burns it with all its grain, unless an army stands on it. Forts keep their grain behind their walls (until bandits take an abandoned one).
- **Supply routes** are a standing order: "keep this fort or supply point stocked to N grain from this village". Every check, it sends the grain missing (counting what is already on the way, at least `orders.supplyMinLoad`) with the caravans at home; what doesn't fit when they arrive comes back.

---

## 7. Threats

### 7.1 Enemy factions
| Front | Faction | Flavor | Signature behaviour |
|---|---|---|---|
| South (+ West at 3+ players) | **Order of the One Throne** (fictional zealots) | Disciplined heavy infantry, crossbows, inquisitors, siege | Prefers razing shrines/villages. Inquisitors damage Sanctity. |
| East (2+ players) | **Nomad horde** | Fast horse archers, raiders | Prefers raiding. Targets caravans and outposts. High mobility. |
| North (always) | **Monster rampages** | Beasts and creatures from Slavic folklore (wolves, likho, leshy-touched beasts, upyri) | Erratic targeting. Spawn lairs. Strong at night. |

The Order is a fictional faction with its own symbols. No real denomination, scripture or real-world religious iconography is used.

### 7.2 Wave schedule (Q13, Q32, Q33)
- **Week 1: grace period.** Only camps, lairs and wandering monsters. Guided quest chain runs during the first 48 h.
- **From week 2:** one wave every **2–3 days** *(tunable)*, rotating fronts, escalating.
- **Public schedule:** front, ETA and a rough threat level. Shown on the map and in the timeline.
- **Quiet hours:** no wave arrivals or battle starts inside the group's quiet window. Anything due inside it shifts to its end.
- **Soft deadline:** waves keep escalating, so a slow group faces rising pressure but is never cut off by a timer.
- **World speed** 1× / 2× scales all timers.

### 7.3 Horde AI (Q12, Q17, Q19)
1. **Spawn** in the front's spawn zone with its composition, stance and commander.
2. **Target selection:** the nearest settlement, weighted by **fear** (fortified positions that beat previous hordes are avoided; fear decays over several waves). Holy City is always a valid target.
3. **Pathing:** A* on the hex graph with terrain cost + fear cost. **Attacks outposts within 1 hex** of the route.
4. **At a target:** decide **raid or raze** by reasoning, not by a fixed chance:
   - Inputs: own remaining strength, defenders and garrisons nearby (and their reinforce range), loot available, time left on the rampage clock, faction personality.
   - **Raid:** quicker, less damage, steals resources, **reinforces the horde** (recruits/loot → strength).
   - **Raze:** slower, destroys the village into a ruin, leaves the horde exposed for longer.
5. **End conditions:** wiped out; reaches the Holy City and fights there (Sanctity damage if it wins); **rampage clock** (12–24 h *(tunable)*) runs out → survivors become a **bandit camp** at their last position.
6. **Difficulty presets** change how smart these decisions are (Story ≈ greedy and simple, Nightmare ≈ looks ahead at reinforcements and fear).

### 7.4 Scouting (Q13)
- Scouts are a **consumable** unit sent toward a front, a horde, a camp or an ancient site.
- Report precision scales with the number of scouts that survive:
  - Few: "~200, mostly cavalry, aggressive".
  - Many: the exact roster, stance, commander and planned target.
- Dangerous fronts kill some scouts. Severian-style clans (Rod Sokola) lose fewer.
- Scouts also **explore ancient sites and borderlands** (see §8).

### 7.5 Bandit camps & monster lairs (Q29)
- **Spawn at the end of each wave**, on unclaimed hexes, weighted toward lanes and fronts. This gives the group a window to clear them before the next wave.
- Also created by: horde survivors (rampage clock) and abandoned forts.
- An **uncleared** camp/lair **adds units to the next wave on its nearest front** and grows slowly over time.
- Capped number of active camps/lairs per world *(tunable)*.
- **Clearing** gives loot: resources, sometimes gear, sometimes Svarog's Ember (lairs).

### 7.6 Difficulty (Q28)
- Wave strength = f(**group power**, player count, bridge stage, wave index, preset), with a **floor** per preset so waves never become trivial.
- Group power counts villages, total army strength and bridge progress. This stops unlimited expansion from out-growing the threat.
- Presets: **Story, Normal, Hard, Nightmare.** Each changes the scaling rate, the camp spawn rate and the AI's smartness.

---

## 8. Exploration, Research & Lore

### 8.1 Ancient sites (Q21)
- Kurgans, sunken shrines, old hillforts, stone idols, frozen ruins.
- Scouts (and later armies with a hero) explore them over real time.
- Outcomes: **hero gear**, resources, **Svarog's Ember**, **lore scrolls**, bridge quest items, or a guardian fight.
- **Searching for ruins:** a village with a Scout Lodge sends 2–20 scouts to search the land up to 5 hexes around it for 3 game hours (`ruinSearch` in `data/scouting.json`). When they are back they have found a forgotten ruin with a 15% chance per scout (at most 90%): a new site on free ground that suits a kind of site, at least 3 hexes from other sites, guarded like any other. The owner hears either way.

### 8.2 Research (Q26)
- **Per-player tech tree** of ~30 techs researched in the Academy, in branches: Economy, Military, Fortification, Scouting, Faith.
- **Lore scrolls** from sites unlock rare techs or grant **group-wide** boosts.
- Per-player trees make it natural for teammates to specialize.

---

## 9. Clans (Q24)

Each player picks a clan (**Rod**) when joining a world. Duplicates are allowed. Each clan has **some** of: best resource, unique unit, unique building, bonus, weakness. Perks live in data files.

Names are animals in Interslavic. **(to verify: spelling/declension with an Interslavic reference)**

| Clan | Animal | Best at | Weakness | Unique |
|---|---|---|---|---|
| **Rod Jelena** | Stag | Grain, fast village growth | Weak cavalry | **Granary-Temple** (building) |
| **Rod Rysa** | Lynx | Wood, ambush bonus | Slower research | **Forest Archer** (unit) |
| **Rod Medvěda** | Bear | Iron, fortifications | Slower expansion | **Stone Redoubt** (building) |
| **Rod Bobra** | Beaver | Caravan speed and capacity | Weaker fortifications | **River Barge** (unit) |
| **Rod Sokola** | Falcon | Cavalry, scouts (fewer scout losses) | Costlier walls | **Border Rider** (unit) |
| **Rod Volka** | Wolf | Stone, cold resistance (north/ice) | Weaker grain | **Longhouse Hall** (building) |

---

## 10. The Kalinov Bridge — Win Condition (Q27)

- The Kalinov Bridge already crosses the Smorodina from Nav to Yav, and the hordes come over it. The group extends it from Yav to **Prav**: joined to the realm of the gods, the bridge is closed to Nav for good.
- Built in the Holy City in **5 stages**.
- Each stage needs a **large shared resource cost** (donations) plus **1–2 quests**, for example:
  - Retrieve a relic from an ancient site.
  - Clear a specific monster lair.
  - Survive a wave with no Sanctity loss.
  - Craft a ritual item (needs Svarog's Ember).
  - Hold a strong point (a choke point or a fort) for a full battle.
- Bridge progress increases wave difficulty (it is part of group power).
- **Stage 5 → Ritual Night:** all active fronts attack at once (respecting quiet hours). Surviving it with Sanctity above 0 **wins the run**.
- **Loss:** Sanctity reaches 0.

---

## 11. Player Experience

### 11.1 The check-in loop (2–5 minutes)
1. Open the app → **home dashboard**: next wave ETA and front, battles in progress, finished builds, teammate requests.
2. Refill queues, adjust standing orders, send scouts or caravans, answer a teammate.
3. Close the app. The server does the rest.

### 11.2 Queues & standing orders (Q23)
- **Order queue limit per village** = a number of orders (not a time span) that grows with village size *(tunable: e.g. 3 → 8)*.
  - **Training queue:** 1 batch, plus 1 for every 5 levels of the Barracks, the Shooting Range and the Stables (`trainingSlotBuildings` and `buildingLevelsPerTrainingSlot` in `data/units.json`).
  - **Standing orders** (repeat training, rebuilding outposts, surplus to the vault, supply routes): 3 per village, plus 1 for every 3 Elder's Hall levels (`maxPerVillage` and `hallLevelsPerOrder` in `data/orders.json`).
- **Standing orders:** repeat training, auto-rebuild after raid/raze, reinforcement rules, auto-caravan surplus to the vault above a threshold, supply routes that keep a fort or supply point stocked with grain.

### 11.3 Notifications (Q23)
- **Push only for:** wave arriving within 6 h, a village/outpost under attack, big build finished, teammate request/delegation.
- Everything else goes into **one daily digest**.
- Respect the device's and the group's quiet hours.
- **Topics:** players switch pushes off by topic in Settings (hordes, battles, outposts, buildings, the bridge and the wilds, the digest; `topics` in data/notifications.json). The phone asks for permission once; the first answer turns every topic on (allowed) or off (denied).

### 11.4 Delegation
- A player can grant a teammate temporary control (e.g. 1–7 days). The delegate's actions are logged and visible.

### 11.5 Onboarding (Q38)
- **Guided quest chain** in the first 48 h: build → queue → claim an outpost → scout → clear the first camp → gift a teammate.
- **Almanac:** in-game reference for every system, unit, stance matchup and clan.

### 11.6 Accessibility & languages (Q39)
- Translation support from day one (Godot translation files, string keys only, no hard-coded text).
- **Launch languages: English, Serbian (Latin script only).** Community translations later.
- Colorblind-safe threat colors **plus icons**. Adjustable text size. Large tap targets.

### 11.7 Art & UI (Q31)
- Godot 2D in the look of **modern grand strategy games** (Civilization VI, Old World, Crusader Kings III): a painterly, naturally coloured map with light and texture, and a quiet interface of dark slate panels, gold accents, Cinzel and Inter (`docs/art-style.md`). Hex tiles and buildings as sprites. (The first pass was flat Kingdom Rush-style art; replaced in M5 step 7.)
- Slavic ornament (embroidery patterns, carved-wood motifs) in UI frames.
- Muted earth palette, bright accents only for threats and actions.
- Placeholder (stock / AI-assisted) art until M5. Until then the UI stays minimal (code-built panels, flat hexes) so the rules can be built and tested first; the **UI design and art pass** (M5) replaces it before launch.
- Portrait-first phone layout. Map pan/zoom with one-finger drag and pinch.
- **Map art:** neighbouring tiles of the same kind merge into one shape (a big forest, a mountain range, a lake) instead of separate hexes; rivers wind along hex edges, with bridges where they can be crossed.
- **Settlements** look different at each level; **banners** show the owner. **Outlines** tell sides apart at a glance: green for yours, blue for allies' units and settlements, red for enemies.
- **Village interior and its resource fields** look and work like Travian's.
- **Battle screen:** a play-by-play of each round with narrative explanations, over a 2D top-down view of the battlefield: units as squares with unit icons, neighbouring squares of the same kind grouped into a squad with one big icon over the whole group.
  - Look: a parchment campaign map like [`docs/reference/battle-map.jpg`](docs/reference/battle-map.jpg) (the Battle of Hastings): shaded hills and ground, roads, rivers and marsh, place names; each side's units as rectangles in its colour with a military-map style symbol for the unit kind, drawn in lines; a label over each group ("Archers", "Bretons"); the leader (a hero, or the horde's chief) as a marker of their own behind the lines.

### 11.8 Support & server costs (Q6, Q37)
- **No ads, no in-app purchases, no speed-ups.**
- "Buy me a coffee" button → external donation page (Ko-fi / Buy Me a Coffee).
- **Server cost slider:** shows this month's server costs vs donations received. Any surplus carries over to the next month. The data comes from a small JSON file the developer updates by hand each month.

---

## 12. Technical Architecture

### 12.1 Overview
```
┌───────────────────────┐   HTTPS (commands)    ┌──────────────────────────┐
│ Godot 4 client        │ ────────────────────▶ │ API (Node + TypeScript)  │
│ (Android first)       │ ◀──────────────────── │  - auth, validation      │
│  - hex map, UI        │   WebSocket (state)   │  - command handlers      │
│  - timers countdown   │                       ├──────────────────────────┤
│  - translations       │ ◀── FCM push ──────── │ Scheduler workers        │
└───────────────────────┘                       │  - one writer per world  │
                                                │  - due-event processing  │
          shared /data/*.json  ◀──────────────▶ ├──────────────────────────┤
          (units, buildings, clans, costs)      │ PostgreSQL               │
                                                └──────────────────────────┘
```

### 12.2 Simulation model (Q34)
- **Server-authoritative.** The client never computes outcomes; it only shows state and counts down timers.
- **Event scheduler:** every timed thing (build done, march arrives, battle round, wave spawn, camp spawn) is a row in `scheduled_events` with `world_id`, `due_at`, `type`, `payload`.
- **One writer per world:** a worker claims a world (Postgres advisory lock / `SELECT … FOR UPDATE SKIP LOCKED`) and processes its due events in order. No race conditions inside a world.
- **Lazy resources:** each village stores `amount`, `rate`, `last_updated_at`. The current amount is computed when read; it is written back only when the rate changes or resources are spent.
- **Determinism:** randomness comes from a seeded RNG per world/battle, so runs are reproducible for tests and bug reports.
- **Quiet-hours shifter:** a single function that maps a due time to the next allowed time. All wave/battle-start scheduling goes through it.
- **Commands** are validated against current state (costs, ownership, queue limits, delegation) inside the world's transaction.

### 12.3 Data model (initial outline)
- `accounts`, `auth_identities`
- `worlds` (seed, difficulty, speed, quiet hours, status, active fronts)
- `world_members` (account, clan, hero, delegation)
- `hexes` (world, q, r, terrain, owner, feature)
- `villages`, `village_buildings`, `village_queues`, `standing_orders`
- `outposts`, `forts`, `camps`, `ancient_sites`
- `armies` (owner, location, stance, setup, reinforce toggle, priority list), `army_units`
- `heroes`, `hero_items`, `research`
- `caravans`, `vault`
- `hordes` (front, composition, stance, target, rampage clock), `fear_map`
- `battles`, `battle_rounds`, `battle_reports`
- `scout_reports`
- `bridge_progress`, `quests`
- `scheduled_events`
- `notifications`, `digests`
- `telemetry_events`

### 12.4 Shared game data
- `/data/*.json`: units, buildings, clans, techs, terrain, stances, setups, factions, difficulty presets, bridge stages, quests, loot tables.
- Edited through a spreadsheet → exported to JSON → validated by a JSON schema in CI.
- The server loads it at startup. The client bundles it for display (names, icons, costs), and the server is always the source of truth.
- Balance changes need no client update when only numbers change (the server sends the current data version).

### 12.5 Protocol & trust (Q35)
- **Commands:** HTTPS + JSON, idempotency keys so retries on flaky mobile networks are safe.
- **State:** WebSocket push of world diffs. Full resync on reconnect.
- **Push notifications:** Firebase Cloud Messaging.
- **Anti-cheat:** server validation of every command + rate limits. Nothing heavier (no PvP, no money).

### 12.6 Accounts (Q36)
- Google (Play Games) sign-in, email sign-in, guest accounts upgradable later.
- Minimal personal data. Account deletion. Privacy policy. GDPR basics.

### 12.7 Hosting & ops (Q37)
- One small VPS (e.g. Hetzner, ~€5–10/month), Docker Compose: API, worker(s), Postgres, reverse proxy with TLS.
- Off-site daily database backups.
- Basic monitoring: uptime check, error logging, disk/CPU alerts.

### 12.8 Repository layout (proposed)
```
/PLAN.md
/data/                 shared game data (JSON) + JSON schemas
/server/               Node + TypeScript
  /src/api/            HTTP + WebSocket
  /src/sim/            pure simulation: formulas, battle, horde AI, mapgen
  /src/scheduler/      event processing, world locks
  /src/db/             migrations, queries
  /test/
/tools/
  /runsim/             headless full-run bot simulator
  /balance/            spreadsheet → JSON export
/client/               Godot 4 project
  /scenes/  /scripts/  /assets/  /i18n/
/ops/                  docker-compose, backup scripts
/site/costs.json       server cost / donations / surplus data
```

The `server/src/sim` module is pure (no I/O, no clock): it takes state + data + seed and returns new state + events. That keeps it unit-testable and lets the headless simulator reuse it directly.

---

## 13. Testing & Balance (Q40)

- **Unit tests** on `sim/`: formulas, battle rounds, stance matchups, raid/raze decisions, quiet-hours shifting, lazy resources, mapgen validation.
- **Headless full-run simulator** (`tools/runsim`): runs a complete world at accelerated time with scripted bots:
  - *Turtle* (few villages, heavy defense)
  - *Expander* (many villages, thin defense)
  - *Balanced*
  - Run across player counts (1–6) and presets. **Target:** waves beatable but tense; Normal win rate ~60–75% for the balanced bot group *(tunable target)*.
- **Data validation** in CI: JSON schemas, cross-references (a unit's building exists, etc.).
- **Light telemetry:** run start/end, outcome, cause of loss, stage reached, wave results. No personal data.

---

## 14. Roadmap (Q41)

| Milestone | Goal | Contents |
|---|---|---|
| **M0 — Tech spike** (~2 weeks) | Prove the stack | Godot hex map with pan/zoom on an Android device. Server scheduler prototype (events, one writer per world, lazy resources). |
| **M1 — Vertical slice** | One playable loop for 2 players | One village each, small map, 4 basic resources, build/train queue, one front (North), public schedule, scouting, basic battle with stances, battle report, WebSocket updates. |
| **M2 — Full economy** | The "builder" game | Village interior view, outposts, caravans, vault, expansion with settlers/upkeep, research tree, heroes, standing orders, queue limits, push notifications + digest. |
| **M3 — Full threat** | The "defender" game | All four fronts + per-group-size rules, the three factions, horde AI (fear, raid/raze reasoning, rampage clock), camps & lairs, field setups, reinforcements with pincer/hit-and-run, ruins & refugee camps, quiet hours. |
| **M4 — Endgame & identity** | A complete run | Kalinov Bridge stages + quests, Ritual Night, clans, ancient sites, gear, lore scrolls, difficulty presets, world speed, delegation, onboarding quest chain, almanac. Headless simulator + first balance pass. |
| **M5 — Beta** | Ready for friends | **2-player playtest** (moved from M1), closed test, balance passes, English + Serbian (Latin) localization, accessibility pass, final-ish art, donation button + cost slider, privacy policy, backups/monitoring. |
| **M6 — Launch** | Play Store | Android release. iOS and desktop afterwards. |

### M0 status
- [x] Repo skeleton: `server/`, `client/`, `data/`, `ops/`, CI workflow.
- [x] Hex math in TypeScript and GDScript, both checked against `data/fixtures/hex-vectors.json`. A* pathfinding on the server.
- [x] Scheduler prototype: `scheduled_events`, one writer per world (Postgres advisory locks), lazy resource ledger, build queue command that catches the world up before acting, failed events isolated. Integration tests cover concurrency, late workers and failures.
- [x] Godot map spike: placeholder world generator (fronts per group size, edge belt, start ring), hex rendering, touch pan / pinch zoom / tap select, Android export preset.
- [x] Run the spike on a physical Android phone and measure frame rate: ~60 FPS on device, so the `_draw()` path is fast enough (no batching needed).

### M1 breakdown (each step is its own PR)
1. [x] **Online foundation:** HTTP + WebSocket API, guest accounts, worlds with invite codes and a lobby, server-side map generation on start (player count decides size and fronts), a village per player, build queue over the API, live updates (Postgres NOTIFY → WebSocket). Client: sign-in, worlds list, create/join, lobby, map from the server, village panel with live resources and build queue. Docker image + compose.
2. [x] **Units:** barracks and scout lodge, training queue (batches train one unit after another, counted lazily), garrison, grain upkeep from the moment units are drafted. Spearman, archer, horseman, scout (`data/units.json`). Starving troops deserting comes later; for now grain just floors at zero.
3. [x] **North front waves:** waves are announced ahead (front, spawn time, threat level; composition hidden), the first after the one-week grace period and then every 2–3 days, growing with each wave and with player count (`data/waves.json`, `data/enemies.json`). A wave spawns in the dark forest / ice, marches to the nearest village by path cost at its slowest unit's pace, and (until battles exist) camps at the gates for the rampage time, then disperses. Client: threat banner, threats timeline, hordes and their route on the map. Only the North front is enabled for now; quiet hours come with M3.
4. [x] **Scouting:** send scouts from your village at a wave (gathering in its spawn zone, marching, or at the gates); they travel by path at scout speed, each survives with the front's survival chance, and the survivors' report (shared with the group) is none / rough (size ±30%, main unit) / detailed (size ±10%, every unit with a range) / exact (6+ survivors), per `data/scouting.json`. Survivors walk home; scouts away still eat, the dead stop. Enemy stance and planned target join the report once they exist (step 5).
5. [x] **Battles:** a horde reaching a village fights its garrison in rounds (every 15 game-minutes, up to 12). Damage uses attack, defense, family counters (infantry > cavalry > archers > infantry), stances (Defensive / Balanced / Offensive / Hold the Line with attack, defense and retreat thresholds), stance matchups and a home bonus, with seeded variance (`data/battle.json`). A side breaks at its stance's loss share; undecided after the last round, the horde withdraws. Defended → the wave is beaten; raided → the horde takes up to 30% of stores (scaled by its survivors) and leaves. Waves have a stance by front temperament, revealed by detailed/exact scout reports. Battle reports are shared with the group. Reinforcements, field setups, raid-vs-raze and walls come in M3.
> **Playtest** *(moved to M5)*: 2 players at 10× for a few days, run once most of the app is done. Setup ready (`docs/playtest.md`): server in Docker on the host's computer, database on Neon, public HTTPS through a Cloudflare quick tunnel; the app can change server address without signing out.

### M2 breakdown (each step is its own PR)
1. [x] **Village interior:** a Travian-style village screen (the **Village** button on the map). 12 resource fields around the outside (3 woodcutters, 3 quarries, 4 farms, 2 iron mines), each upgraded on its own; 12 building slots in the center, the first holding the Elder's Hall. Hall level 1 opens 4 slots, each further level one more; every 3 Hall levels add a build-queue place (2 at the start); each level builds 4% faster. Build orders name a plot (`{ plot, building? }`); older villages are laid out on plots when the server starts.
2. [x] **Outposts:** claim a forest, plains, hills, mountain or lake hex within 2 of the village; the outpost is built and upgraded (to level 5) through the village's build queue, and what it gathers depends on the terrain (`buildings.json` → `outpost.yields`). A village holds 1 outpost, plus 1 per 2 Elder's Hall levels. A marching horde burns every outpost within 1 hex of its route down a level (to ruins at 0, which can be rebuilt or abandoned); raids are shared with the group. While a battle rages at a village, its outposts produce nothing.
3. [x] **Caravans and the Holy City vault:** a Caravan Yard gives one caravan per level, each carrying 500 (`data/logistics.json`). Caravans take the road at their own pace (terrain slows them) to an ally's village or the vault, unload what fits, and walk home with the rest. Empty caravans can fetch from the vault, bringing back whatever it holds when they arrive. The vault is shared, holds 3000 of each resource at level 1 (×1.5 per level), and any member can enlarge it, paid from the vault. Interception by hordes and bandits, and escorts, come with M3.
4. [x] **Expansion:** a Settlers' Lodge trains settlers, whose cost grows ×1.5 for every village you own. Three settlers walk (at settler pace) to a settleable hex within 6 of their village, at least 3 from every village and 2 from the Holy City, and found a village there with its own starting stores; if the site was taken meanwhile they walk home. The n-th village pays (n − 1) × 3 grain per hour for administration, and the Troops tab suggests a garrison of 10 + 5 per extra village (`data/expansion.json`). The client switches between your villages (village picker; tapping one on the map).
5. [x] **Research:** a per-player tree of 26 techs in five branches (Economy, Military, Fortification, Scouting, Faith; `data/research.json`), researched one at a time in an Academy whose level gates each tech; the village that starts a tech pays for it. Effects add up per player and reach all their villages: production by resource, outpost yield, storage, build and training time, troop upkeep, attack and defense by family, defense at home, loot raiders take, caravan speed and load, scout speed and survival. The Research tab shows which teammates know each tech. Lore scrolls come with ancient sites (M3).
6. [x] **Heroes:** one per player, named from Slavic lore (renamable), standing in one of their villages and leading its garrison (`data/heroes.json`). Skills in three branches (Warlord, Warden, Wayfinder) and gear in five slots (weapon, armor, amulet, banner, mount, with two sets) use the same effects as research and count for battles at the hero's village and for scouts and caravans sent from it. XP comes from enemies slain in battles the hero fights in (one skill point per level, up to 20); a beaten horde may leave gear; a lost battle wounds the hero for 8 game hours. Heroes travel between their player's villages (not out of a battle). Leading armies and gear from sites, lairs and camps come with M3.
7. [x] **Standing orders** (`data/orders.json`), up to 6 per village, run when placed and then every 20 game minutes, each showing what it last did: **repeat training** keeps a unit topped up to a target, a batch at a time (counting units at home, away and in training); **rebuild** restores raided outposts to the best level they reached; **surplus** sends everything above a share of storage to the vault with the caravans at home. Reinforcement rules come with armies (M3).
8. [x] **Notifications and digest** (`data/notifications.json`, [docs/push.md](docs/push.md)): pushed outside a player's quiet hours for a horde due within 6 game hours, a battle at their village, a burned outpost or a big build; everything else (builds, research, battle results, deliveries, settlers, hero news) goes into one daily digest at their digest hour. All of it lands in an in-app inbox with quiet-hour and digest settings. The server pushes through Firebase Cloud Messaging once given a service account; the app's token registration waits for the Firebase project (`google-services.json`). The group's quiet hours for waves come with M3.

### M3 breakdown (each step is its own PR)
1. [x] **Armies and reinforcements** (`data/armies.json`): send fighting troops from a village to any village of the group as an army on the map (they still eat at home). **Support** armies stand guard there and fight its battles until called home; **reinforce** armies join the battle there from the next round and go home after; **harass** armies (mostly cavalry) strike one round with a bonus, take only 30% of their losses and ride home. A reinforcement arriving from a different side than the horde gets a **pincer** bonus on its first round, scaled by its size against the horde's. Every village answers battles near it (default: half its troops to any battle within 4 hexes; editable per village, 0% to stay out). Losses are shared between the garrison and the armies by what each brought; battle reports name who came to help.
2. [x] **Field battles and setups** (`data/field.json`): an army sent to **hold** a hex digs in and meets every horde whose road runs through it, in a field battle there (rounds as at a village, no home bonus; the holders fight with their owner's research and stance). The ground helps: an **ambush** (+30% attack and the horde loses its stance in the first round) on forest, hills or swamp when the army was in place an hour before the horde; a **choke point** (3+ impassable neighbours) cuts the horde's attack to 70% and adds +30% defense to Hold the Line; a **fort** (built from a village within 4 hexes, paid from its stores) adds +30% defense. Holders who win stay on the hex; beaten, they fall back home and the horde marches on, late by the time it fought (its raids and later intercepts are planned again). A hero can lead an army, adding their skills and gear, gaining XP from its battles and coming home wounded if it is beaten. Abandoned forts turning into bandit camps come with camps (step 5).
3. [x] **All fronts and factions** (`data/enemies.json`): waves rotate through every active front (solo: North and South; 2 players add East; 3+ add West). Each front has its own roster and spawn zone: **Monsters of the North** (grey wolves, Leshy's thralls, cave bears, volkolaks, upyri, likho, and zmey whelps for groups of 3+) from the dark forest and ice; the **Nomad Horde** (steppe raiders, horse archers, lancers, shamans, the Khan's guard) from the steppe; the **Order of the One Throne** (zealots, crossbowmen, knight-brothers, inquisitors, siege rams) from the hallowed lands. Units can be held back for bigger groups (`minPlayers`). Faction personalities: stance temperament, **greed** (share of a raid carried off: nomads ×1.5, Order ×0.8, monsters ×0.6), **raid reach** (nomads burn outposts 2 hexes from their road) and **nerve** (the Order holds to ×1.25 its stance's retreat point, nomads break at ×0.85, monsters ×1.15). Scouts survive less often against the nomads. Client: hordes coloured by faction, a Fronts section in the threats panel. Targeting by personality comes with the horde AI (step 4).
4. [x] **Horde AI** (`data/horde.json`): hordes pick the cheapest target by road, **fear** and faction (monsters choose erratically); the Holy City is always a target. Beating a horde leaves fear at that hex (more for every horde killed there), which fades with every new wave and makes hordes route around it and pick other targets. A horde that beats a village decides **raid or raze** by reasoning: the first two waves only raid; later ones raze when they have the time left on their rampage clock, outnumber the help that could come (villages whose reinforce rule covers it) and their faction leans that way (the Order burns, nomads plunder). A raid takes loot and recruits 10% more; a raze takes 3 game hours and leaves a **ruin** (everything at level 0, stores and troops gone) that can be **rebuilt** for 40% of what stood, over 6 hours. A player left with only ruins gets a **refugee camp** near the Holy City, which hordes raid but never raze. The **rampage clock** (18 game hours from the first target) sends a horde on to the next village it hasn't struck; when it runs out the survivors settle into a **bandit camp** (or a monster lair) on a nearby hex. Hordes reaching the Holy City fight its guard (growing each wave) plus any army holding it; if they win, the city loses Sanctity per survivor, and at 0 the run is lost (the world stops). Client: ruins, refugee camps and camps on the map, a rebuild panel, raid/raze reasons in battle reports, Sanctity in the threats panel, fear shown on a hex.
5. [x] **Camps and lairs** (`data/camps.json`): when a wave ends, a camp of its front rises near its road, away from villages (up to 6 at once; monsters make lairs), sized by the wave; horde survivors and forts left unheld for 48 game hours become camps too. Camps grow 10% a day and send half of themselves with the next wave of their front. Armies sent to **clear** a camp storm it on arrival (it fights from behind its palisade); if they win they carry its loot home (resources per camp unit), a hero leading them may find gear, and lairs may give the group a **Svarog's Ember**. Camps **ambush caravans** passing within a hex: unless the caravan's **escort** (troops sent along, back when it returns) matches the camp's strength, it loses half its load and the escort some troops. Nothing can be built or founded on a camp's hex. Client: camps on the map and in the threats panel, a Clear this camp form, caravan escorts and ambush reports, embers in the vault panel.
6. [x] **Quiet hours and difficulty** (`data/difficulty.json`): a world is created on **Story, Normal, Hard or Nightmare**. The preset scales every wave (×0.7 to ×1.5), with a floor so waves never become trivial and a cap, and **group power** raises it further: every village beyond one per player, and an army whose total attack is above an expected curve (600 per player, +15% a wave). Presets also set how many camps rise after a wave (×0.5 to ×2), how much hordes heed fear (Story hordes don't learn), how readily they raze and how many early waves only raid. The host sets the group's **quiet hours** (in their time zone): a horde due to arrive inside them waits outside its target until they end, for first arrivals, onward marches and marches resumed after a field battle. Client: difficulty when creating a world; difficulty and quiet hours (host buttons) in the threats panel.

### M4 breakdown (each step is its own PR)
Difficulty presets and world speed already exist (M3 step 6, M1).
1. [x] **Ancient sites and lore scrolls** (`data/sites.json`, `data/lore.json`): kurgans, sunken shrines, old hillforts, stone idols and frozen ruins (3 per player, at least 5) are placed when a world starts, mostly in the borderlands, some mid-map, away from start sites; 20–70% are watched by guardians (beasts of the North, more the further out), unknown until someone fights them. Armies (scouts may go too) sent to **explore** fight any guardians, search the site for 3–8 game hours and come home with one find: resources (more the further out), a piece of hero gear, a Svarog's Ember, or a **lore scroll** the group lacks. Scrolls serve the whole group: five add group-wide boosts (grain, caravan load, attack, storage, defense) and two unlock **rare techs** (Wind Riders, Ember-Forged Arms) that every member can then research. Nothing can be built on a site's hex. Client: sites on the map, an explore form, finds, the group's scrolls in the Research tab.
2. [x] **Kalinov Bridge:** five stages built in the Holy City from the vault (villages fill it by caravan) and Svarog's Ember, each with 1–2 quests (bring a relic from an ancient site, clear a named lair, survive a wave without losing Sanctity, hold a choke point or a fort through a battle, craft a ritual item). Every stage and every quest carries its story reason (`data/bridge.json`), shown in notices and the Holy City panel. A paid stage with its quests done is raised over 12 game hours. Bridge stages standing count towards group power.
3. [x] **Ritual Night and the end of a run:** finishing stage 5 calls Ritual Night: the waves still to come are called off and every active front sends one horde (1.5× strength), all setting out together 6 game hours later (after quiet hours). The group wins when the last of them is beaten or gone and the Holy City still stands; it loses when Sanctity reaches 0. Each ending has its story (`data/bridge.json`), told to everyone. Win and loss screens show the story and a summary of the run (days, hordes beaten, battles, camps, sites, scrolls, villages, each member's villages); a finished world stays readable and refuses commands.
4. [x] **Clans:** six clans (Rod Jelena, Rysa, Medvěda, Bobra, Sokola, Volka), each with a story, picked in the lobby (a member who joined without one picks once in the run). Each has a best resource or skill, a weakness and a unique unit (Forest Archer, River Barge, Border Rider) or building (Granary-Temple, Stone Redoubt, Longhouse Hall, whose effects grow per level) only it can train or build (`data/clans.json`). Clan effects join the player's research bonuses; new effect keys: `researchTime`, `fortCost`, `coldDefense` (against the North), `ambush` and `trainTime.<unit>`.
5. [x] **Delegation:** a player hands a teammate temporary control (1–7 days) over their villages (no chains: someone who handed theirs over can't take on more). The delegate commands them as their own (building, training, research, scouts, outposts, settlers, caravans, armies, forts, standing orders); every action is logged and shown to the group. The owner can take them back and the delegate can hand them back early; heroes stay with their owner.
6. [x] **Onboarding and almanac:** a getting-started chain (`data/onboarding.json`: raise a building, train defenders, claim an outpost, send scouts, clear a camp, gift a teammate or the vault), each step with the village elder's reason and a reward to the player's first village the first time it is done; the next step shows on your village. An in-game almanac (from the Threats panel) of units, buildings, stances and counters, hordes, clans, terrain and how a run is won or lost, written from `data/`.
7. [x] **Headless simulator and first balance pass:** `npm run sim` (`server/src/runsim`) plays whole worlds with scripted bots (turtle, expander, balanced) through the real commands, scheduler and database on a simulated clock, across player counts and presets, and reports how each run ended (won, lost and to which front, or unfinished and on what), the bridge stage, Sanctity, villages and hordes. First pass:
   - **Bugs it found:** a raid didn't clear the village's build queue (it now does, like a raze); the rebuild order lost a queued outpost rebuild when a later one couldn't be paid for; completion events of cleared builds failed instead of passing.
   - **Content it ran out of:** Svarog's Embers (sites find one more often, lairs give one 75% of the time, the last two stages need 1 and 2), lairs (the camp limit is per front, 4 each, and a lair rises when a stage wants one and none stands), relics (a forgotten ruin appears when a stage wants one and every site was searched), choke points on horde roads (the strong-point quest also counts a battle won from a fort).
   - **Pace:** waves grow 1.18× per wave (was 1.25×, which outran any economy by day 40; 1.15× never threatened). Balanced groups now win in 33–55 days or fall to Ritual Night itself.
   - **Still to do** (the bots, then the numbers): teammates coordinating strong points, late-game Ember gathering, enough runs per player count and preset for real win rates against the 60–75% target.

### M5 breakdown (each step is its own PR)
Art may be generated at first, as long as the style is consistent: clean and simple but distinct, every piece recognizable at a glance and still good-looking, and easy to replace later with the developer's own art (see `docs/art-style.md`).
1. [x] **Art pipeline and style sample:** art addressed by id through `client/art/art.json` (an `Art` loader with a fallback, so any file, SVG or PNG, can be swapped by pointing its id at it), a first generated set (`tools/art/generate.py`: terrain, settlements in five stages by Elder's Hall level, ruins, the Holy City, banners, camps, lairs, forts, outposts, ancient sites, units, horde emblems, resources and the app icon), the style rules (`docs/art-style.md`) and a style sample rendered by the game (`docs/art/style-sample.png`), for approval before the rest.
2. [x] **Map art:** terrain drawn from the art, neighbouring tiles of one kind merged into regions (forests, mountain ranges, lakes); settlements by level with owner banners and green/blue/red outlines; camps, sites, forts, armies, caravans and hordes as icons.
3. [x] **Rivers and bridges:** mapgen lays rivers along hex edges, from hills and mountains downhill to lakes, swamps or the edge belt (25–45 edges a map), with a bridge every few edges and on every road a front or a start needs, so the map stays playable. Nothing crosses a river without a standing bridge: armies, hordes, caravans, settlers, scouts and heroes route around. Players build bridges within 4 hexes of their village (`POST /v1/villages/:id/crossings`, 2 game hours); hordes use them too. Drawn on the map; the hex panel lists the rivers along a hex and offers a bridge.
4. [x] **Roads:** players build roads between neighbouring hexes within 4 hexes of their village (`POST /v1/villages/:id/roads`, not across an unbridged river, half a game hour). Moving along a road costs half the terrain (`field.road.levels`) for armies, caravans, settlers, scouts, heroes and the human hordes, whose routes now prefer them; the Monsters of the North keep off them. Drawn on the map as tracks; the hex panel offers a road towards each neighbour.
   - **Road levels:** a road can be improved twice (the same route on a standing road): level 2 costs 35% of the terrain (200 wood, 350 stone, 75 grain, 25 iron, 45 game minutes), level 3 costs 25% (300 wood, 500 stone, 100 grain, 75 iron, an hour). A road keeps its level while it is improved. Roads from before are level 1. Drawn wider at each level; the hex panel lists each road's level and offers to improve it.
5. [x] **Village interior:** the village view drawn from the art: a meadow of resource fields around a palisaded square of building plots. Every building and field has art in three stages (levels 1–3, 4–7, 8+; `building/<kind>_<stage>`, `field/<kind>_<stage>`), with a level badge, a gold ring while being built and a white one when picked; open plots are staked out, locked ones overgrown under a padlock with the Hall level that opens them.
6. [x] **UI pass:** one theme for every screen (`UiTheme`), in the manner of modern grand strategy games: dark slate glass panels with a bronze trim and a soft shadow, flat buttons with a gold primary for the main action, underlined tabs, Cinzel headings and Inter text (both cover Serbian Latin); vector styles, sharp at any scale, replaceable by art. A top bar with the world, the map/village toggle and the inbox, a resource strip (icon, stock, rate) and a slim threat line; white line icons the theme tints; resource icons in every cost line. (The first pass, wooden Kingdom Rush-style frames, was replaced on review.)
7. [x] **Modern art:** the map with texture and light (`MapGround`: one shaded mesh where terrains blend, noise grain, relief, water sheen; `MapFeatures`: shaded woods, peaks, hills, reeds and stones, several to a hex), and every piece redrawn in one shaded, outline-free style lit from the upper left: settlements in five stages, the Holy City, camps, forts, outposts, sites, units on enamel medallions, faction shields, resources, banners, village buildings and fields, the start picture at dusk and the app icon.
8. [x] **Battle screen:** a **Battle map** button on every battle (reports and battles being fought) opens it in place of the map: a parchment campaign map (reference: `docs/reference/battle-map.jpg`) with the battlefield's own ground (woods, marsh, hills, its river and road), our squads above and the enemy's below, each unit type one run of blocks with its map symbol (infantry ✕, cavalry a slash, archers a dot) in the side's colour (green yours, blue an ally's, red the enemy) under one label with its icon; fallen blocks stay as ghosts, reinforcements wait as ghosts until their round, the lines close in round by round, leaders (your hero, their chief) stand behind as oval markers, and the end shows Victory or Defeat. Step through the rounds or play them; each round is told in words (`BattleStory`: who joined and how, what fell on each side, how the lines hold, how it ended). Battles now carry the enemy's front.
9. [x] **Enemy heroes:** every front has one named leader at a time (`data/leaders.json`, `sim/leaders.ts`): Mara the Hungry for the Monsters of the North, Beg Konchak for the Nomad Horde, Brother Anselm for the Order, rising in rank (the Dread, Khan, Commander; the Deathless, Great Khan, Grand Master) as they level. They take the head of their front's hordes as they set out (unless wounded or already out), and grow like player heroes: experience from every battle, more for a win or a raze, levels up to 15 with a skill each level in their front's order (Savagery: attack, Thick Hide: defense, Dread: holding longer, Greed: plunder). Beaten, they flee wounded (30 game hours) and swear revenge on the village that beat them (+15% attack there); if their horde falls to the last, they fall with it and a rival rises at a third of their level. The group hears when one falls or grows stronger. Shown in the threats panel (rank, level, state, skills, record, grudge, the fallen), on each wave ("Led by…"), on the battle map and in the battle story. Camps keep their unnamed chiefs for now.
10. [x] **Walls and siege** (`data/walls.json`, `sim/walls.ts`):
    - **Walls** are their own structure (plot `w`, the gate in the village view), upgradable to level 10 through three tiers: Palisade (1–3), Stone Wall (4–7), Fortress Walls (8–10). While they stand the garrison defends 3% better per level, and a horde must batter them down: 120 integrity per level. Older villages get room for walls on server start.
    - **Wall slots** (plots `t0`–`t4`) open at wall levels 1, 3, 5, 7 and 9, on the ring between the fields, and take one tower each, built and upgraded on their own (to level 10): **archer tower** (+5% garrison attack per level while the walls stand), **gate tower** (+8% wall integrity per level), **ballista platform** (smashes 0.35 siege engines a round per level, the biggest first), **murder holes** (+4% defense per level while the walls stand), **ditch and stakes** (keeps off 5% of the battering and slows engine building 10% per level; the moat since step 11), **watchtower** (warns of a horde an hour earlier per level).
    - **Siege:** every enemy unit batters walls each round with its `siege` (rams 40, catapults 60, ladders 6; cave bears, volkolaks and zmey whelps a little), or 2% of its attack. Engines brought along march at their pace (rams and catapults are slow). A horde that couldn't breach within 6 rounds builds its front's engine on site first (the Order: rams, 3 h × 0.8; the Nomads: scaling ladders, 3 h × 1.6; the Monsters of the North: none, they claw at the walls with what they have), and the assault waits for them, giving help time to arrive. The Order fields catapults from wave 6 (2+ players).
    - **Breach:** at 0 integrity the walls fall; their bonuses are gone, and after the battle they stand a level lower.
    - Client: the walls ring the village square by tier (pegged line, palisade, stone, fortress), the gate and the slots are plots with their art, the build panel describes walls and towers; the battle map draws the walls between the lines (their strength, cracks, the breach), the lines close only once they fall, and the story tells the siege works, the battering, the ballistae and the breach.
11. [x] **Walls part 2, rivers and the village circle** (asked for after step 10):
    - **Materials:** the walls rise through four tiers of sturdier material, each multiplying their integrity: Palisade (wood, 1–2, ×1), Timber Rampart (earth and timber, 3–4, ×1.15), Stone Wall (5–7, ×1.35), Fortress Walls (8–10, ×1.6).
    - **Men on the walls:** the walls hold 30 men a level, archers first; archers up there shoot 4% harder per wall level.
    - **Escalade:** while the walls stand, the horde's fighters (not its archers) strike at half strength, except the share that climbing engines carry over: scaling ladders (8 men a round each) and **siege towers** (30; the Order brings them from wave 5, 2+ players, slow). Men over the walls also take that share of the walls' shelter away. A horde builds its front's engine on site: the Order's southern host rams (to breach in 6 rounds), its western host siege towers and the Nomads ladders (to carry 60% of their fighters over each round), in 3 h × siegeCraft × the engine's set-up factor (ladders 0.6, towers 1.5). Ballistae smash climbers too.
    - **Moat:** the ditch tower is now the moat, dry with stakes and holding water from level 4; besides cutting the battering and slowing engine building it keeps 6% of the climbers off per level.
    - **Rivers:** a horde that crossed a river (over a bridge) into the hex it fights in strikes at 80%, at walls or in the field ("river crossing"). On the battle map rivers are broad obstacles, never streams: across the field with the bridge where the horde came over, else down a flank, where the lines keep off it.
    - Client: the battle map draws the walls from border to border in their material (logs, timber on an earth bank, coursed stone, fortress towers), the moat before them, our archers on them, the enemy's engines at their foot (ladders leaning, towers against them, rams before them) and climbers on them; the village view draws the walls by material (fortress bastions between the slots) and the moat around them, and the building slots in a circle around the Elder's Hall in the middle, paths running out to each.
12. [x] **UI/UX rework** with the frontend-design skill (`.claude/skills/frontend-design`; plan and review in `docs/art-style.md`, "The interface"):
    - The slate-and-gold frame and Cinzel capitals were the stock fantasy-strategy look. Now: a band of dark wood along the top, sheets of unbleached flax with ink lettering, and one ornament, a strip of rushnyk cross-stitch (`Rushnyk`) under the band.
    - Colour carries side: malachite for ours and the main action, madder for hordes and danger, wheat for resources and levels.
    - Type: PT Sans for text, Old Standard for headings (the battle map too), and Ruslan Display for the logotype alone. All are in sentence case and cover Serbian Latin and Cyrillic.
    - The map is the hero. In landscape the sheet stands on the right, the resources ride in the title row and the camera centres on the uncovered map; in portrait the sheet sits below. Landscape screens are laid out on 1600×1100 instead of shrinking the phone layout to 70%.
    - The start screen is one centred column, with the language picker on its sheet.
    - Keyboard focus shows, and the threat line reads as a sentence ("Next horde from the north (low threat) sets out in 1h 40m").
13. [x] **Asset pass** with the game-assets-enhancement skill (`.claude/skills/game-assets-enhancement`). The style guide, lighting rules, layer stack and sprite manifest are in `client/art/STYLE.md`.
    - **Audit:** enemy units had no art at all, the siege engines had none, the walls had three level stages against four materials, and a map feature (the menhir) could pass for a stone idol site.
    - **Enemy units:** all 21 have medallions (an iron rim run with madder, against our gold), with shapes reused where kinds share them. Engines are included: ladder, ram, catapult, siege tower.
    - **Walls** are drawn by material (`building/wall_wood`, `_timber`, `_stone`, `_fortress`).
    - **Hallowed ground** grows flowering grass in place of the menhir.
    - **Light grade** (`MapGrade`): a code grade over the map with a warm wash from the upper left, slow cloud shadows that slide a little faster than the ground when it pans (parallax 1.15), and a vignette round the map in view.
    - **Fix:** level and upright lines filled with a gradient drew nothing, which had cost the archer's arrow its shaft.
    - **Settlement view** (asked for on review):
      - The land runs to the edges of the view with the map's own grain, relief and light (`VillageGround`, the ground shader): the square's beaten earth, a clearing of meadow, a road out of the gate, and beyond it wild grass and woods, each tree its own sprite placed by the village's seed.
      - Nothing is a perfect circle. Fields, walls, moat, slots and towers follow each village's own outline (`VillageView.wobble`), and the clearing's edge swells further, where nothing stands. Plots stay clear of each other for any village (tested over many seeds).
    - **Still to do:** painting the manifest through the skill's fal.ai pipeline needs a fal.ai account, key and MCP server.
14. [x] **Localization:** English and Serbian (Latin); every string in translation files, server notices included. Groundwork done (`docs/localization.md`): gettext files, the extractor with a CI check, the language picker, the start screen and every data text in Serbian. Every client UI string is wrapped and translated (885 strings); data-driven names are wrapped at display; server notices render in the player's language (`accounts.language`, `server/src/i18n.ts`).
15. [x] **Accessibility:** colour-blind-safe threat colours plus icons (skull tiers), adjustable text size, large tap targets.
16. [x] **Support and privacy:** the donation button and the server-cost slider (§11.8, `site/costs.json`), a privacy policy (`docs/privacy.md`), account deletion and data export, plus a **Report a bug** button that sends the player's message with the current game state and saves it as a file.
17. [x] **Production** (`docs/production.md`, `ops/production/`):
    - **Image:** every merge to main publishes the server image to GitHub's container registry (`ghcr.io/<owner>/slavian-server:main` and `:<sha>`).
    - **Deploy:** on a VPS, Docker Compose runs it behind Caddy (HTTPS on your domain, renewed by itself), on Neon or a local Postgres. The Firebase key and the month's costs are mounted files, not baked in.
    - **Backups:** a `pg_dump` every night with 14 days kept, and by hand with `BACKUP_ONCE=1`; on top of Neon's point-in-time restore.
    - **Monitoring:** `/health` answers 503 while the database doesn't, for an uptime monitor. Failed scheduler events and passes, server errors, crashes and failed backups post to a Discord or Slack webhook (`ALERT_WEBHOOK_URL`), at most once per kind every 10 minutes.
    - **Telemetry (§13):** run start and end (outcome, the front that struck the last blow, bridge stage, days, counts) and every wave's battle, with no personal data; `npm run telemetry` sums it up (win rate, losses by front, waves held by front).
18. [x] **Brand, splash and plated wood** (asked for after step 17; `docs/art-style.md`):
    - **Wood:** the interface's wood is walnut plated in gold: rails with rivets, and corner plates with a cut lozenge (`PlatedWood`).
    - **Logo:** a gold lozenge emblem with the Holy City and the Kalinov Bridge at dusk, and SLAVIAN cut from Ruslan Display and plated in gold. The emblem is also the app icon.
    - **Start screen:** full-bleed. A dusk painting holds the logo, and the sheet sits beside it (landscape) or under it (phone) in plated wood. Language and text size share one row.
    - **Splash:** the studio's logo (Night Forge, `client/art/brand/night_forge.png`), then the game's logo with one gold shine; it can be skipped.
    - **Town names** (asked for after this step): every town gets a Slavic name of its own (`data/names.json`; old roots and endings once the list runs out), unique in its world, and its owner can rename it. The village panel's header steps through the player's towns with ◀ and ▶. Old towns named "Mila's village 2" are renamed on start.
19. [x] **Rivers that make sense** (asked for after step 18; `sim/mapgen.ts` `layRivers`):
    - Every river ends where water takes it: at a lake, at the ocean or off the edge of the map. It may run on through the edge belt to get there, and it never ends in a swamp or in the middle of the land.
    - Rivers merge: a later river that reaches a corner where an older one runs joins it, and rivers are drawn towards each other a little. Each edge has a **size** (1 from the source, +1 for each river joined above; migration 033), and the map draws a river wider below each meeting point.
    - A river runs only between two land hexes, never along a lake's or the ocean's shore, so no bridge leads onto water. Building a bridge onto a lake or the ocean is refused, for rivers on older maps too.
20. [x] **Resources every minute** (`sim/resources.ts`, client `Ledger`): production is credited once a minute, a minute's worth at every whole minute (UTC) since the ledger was settled, so settling never gains or loses anything; upkeep is taken the same way. The title row shows each rate per minute, and its tooltip gives the hourly figure and the seconds to the next credit. Shared cases in `data/fixtures/resource-vectors.json`.
21. [x] **Hero roster** (`data/heroes.json` `roster`, `sim/heroes.ts`): six heroes to pick from, each with strengths and weaknesses, a trait and a painted portrait (art `hero/<id>`, from `tools/art/generate.py`):
    - **Dobrynya**, the serpent-slayer prince: attack and cavalry, but his retinue eats more (upkeep); *Rallying cry* (defense at home).
    - **Vasilisa**, the forest huntress: archers and ambush, weaker infantry defense; *Tracker* (hero and scout speed, scouts come back alive).
    - **Volkh**, the wise volkhv: faster research and more grain, weaker attack; *Healing rites* (half the time wounded, more XP).
    - **Sadko**, the merchant rider: caravans and production, weaker defense; *Silver tongue* (raiders carry off less).
    - **Nastasya**, the shieldmaiden: defense, slow on the road; *Unbreakable* (spearmen train faster, defense at home).
    - **Ilya**, the old bogatyr: attack and defense, learns slowly (XP); *Strength of the earth* (less time wounded).
    - Each member picks in the lobby (`PUT /v1/worlds/:id/hero`), one nobody else in the group has, and may change it until the start. Whoever didn't pick gets the first free hero in roster order. Runs from before the roster gave each player one on the server's start (migration 034).
    - A roster hero's strengths, weaknesses and traits reach all of the player's villages, like a clan's perks. Skills and gear still count where the hero stands. Hero-only effects: `heroSpeed`, `heroXp`, `woundTime`.
    - Client: hero cards in the lobby (portrait, story, effects, trait, who has which), and the portrait, title and traits at the top of the hero panel. Portraits in battle reports come with the hero quests (step 22).
22. [x] **Hero quests** (`data/quests.json`, `sim/quests.ts`, `scheduler/quests.ts`): the hero rides out alone (status `questing`) for real time, the road there and back at its own speed plus the work, and comes home with XP (times its `heroXp`) or, by a fixed chance per quest, wounded. While away it leads no garrison.
    - **Ambush the horde's road:** the next horde from a front sets out 6 game hours later.
    - **Ride beyond the border:** an exact scout report on the next horde from a front, in the threats panel.
    - **Find the lost caravan:** resources to the hero's village, more as the hero rises in level.
    - **The smith's hoard:** a piece of gear the hero doesn't have.
    - **Search the ruins:** the hero searches the nearest unguarded ancient site in person, with the same finds as an army's search (`claimFind`).
    - The hero is offered three at a time from what the world holds (a horde not yet set out, an unguarded site, gear left to find), new ones every 8 game hours, never one it already went on (`POST /v1/worlds/:id/hero/quest`). Offers and the quest under way are in the hero view; the hero panel lists them with time, risk and XP, and counts down the return. The player hears what came of it.
    - Still to do: the hero's portrait in battle reports.
23. [x] **How to play, made visible** (the getting-started chain of M4 step 6 was easy to miss, didn't say how, and its reward came silently; `data/onboarding.json`, `scheduler/onboarding.ts`, client `QuestCard`):
    - **Visible:** a quest card floats at the top left of the map and the village while the chain is open. It shows the progress ("Getting started 2 of 6"), the step, and its reward with icons. It folds to a line, and glows while a reward waits.
    - **How:** each step lists what to tap (`how`). **Show me** goes to the right place and rings the control: the Village button, Build or Upgrade, the Troops and Caravans tabs, the threat line, a claimable hex next to the village, or the nearest camp.
    - **Claim:** a done step's reward waits until the player taps **Claim reward** (`POST /v1/worlds/:id/onboarding/claim`). It goes to the first village in full, even past the stores' capacity, and the resources fly into the title row. Steps done before this count as claimed (migration 036).
    - **Quick start:** step rewards doubled, and claiming the last one also brings the chain's own reward ("Ready for the hordes": 800 wood, 800 stone, 800 grain and 500 iron).
    - **First run:** a welcome card says what the run is about and points at the quest card; it can skip the tutorial. **How to play** in the almanac brings both back. Both are kept per world on the device.
24. [x] **Local single player** (asked for after step 18): a solo world runs entirely in the app, with no calls to the server.
    - **How:** the rules, the scheduler and the battles are ported to GDScript as an in-app local server (`client/scripts/local/`). It answers the same API calls the client makes today, so the screens don't change. Worlds are saved on the device.
    - **Co-op** keeps the TypeScript server. Both sides run the same shared fixtures (`data/fixtures/`), as the hex math already does, so the two rule sets stay in step.
    - **Order:** data and the sim core (resources, building, training), then the scheduler and catch-up, waves, hordes and battles, then the rest (outposts, caravans, research, heroes, sites, the bridge), each with its fixtures.
    - **Progress:**
      - [x] **The map:** the seeded RNG (mulberry32 in 32-bit integer arithmetic), simplex noise, the server's A* (same heap, same ties) and map generation with rivers and bridges (`client/scripts/local/`). The server writes `data/fixtures/mapgen-vectors.json` (`npm run fixtures`; a server test fails while it is stale), and the client test makes the same five maps from it, terrain, starts, rivers and bridges, exactly. The game data the server reads is bundled into the app (`client/data/game.json`, `LocalData`). The design and the order of the remaining parts are in `docs/local-engine.md`.
      - [x] **Starting a solo world and opening it with no server** (`LocalServer`, autoload `Local`): the world starts as on the server: the map, the town name, the village, the roster hero, the player's bonuses, the ancient sites, the bridge, the vault and the first waves with their spawn events. Its world view is the server's, field for field: the server test `start-fixture.test.ts` records a real start as `data/fixtures/start-world.json`, and the client test starts the same world and compares every value. Worlds are saved under `user://local/` and read back. While a solo world is open, `Api` hands requests to the local engine and `Live` needs no connection; requests not ported yet answer "Not in single player yet".
      - [x] **Villages:** building (fields, slots, the queue and its limit), training (and the upkeep it brings), outposts (claiming, building, abandoning), the stance, renaming, and claiming getting-started rewards, with the server's checks and messages word for word. Due events run before each request and every second while the world is open (`build_complete`, `training_complete`; events not ported yet wait), and the screens get the same live updates. The server test `village-scenario.test.ts` records a 25-step solo session, answers and waits included, as `data/fixtures/village-scenario.json`; the client test replays it and gets the same answers.
      - [x] **Hordes setting out:** `wave_spawn` in the app: the front's leader takes the horde's head (or a new one rises), camps of its front join it, fear fades, the march is planned (spawn hex, route, target, the time of every step, held past the group's quiet hours), raids on outposts along the route and the warning are scheduled, and the next wave is announced, sized to the group's strength. The walls' rules are ported for the warning and the battles to come. The world view gains the leaders and fear. The server test `wave-scenario.test.ts` records a horde setting out, up to a minute before it arrives, as `data/fixtures/wave-scenario.json`; the client test replays it. Scenario tests share `server/test/scenario.ts`.
      - [x] **Battles and the horde AI:** hordes arrive and fight in the app: village battles round by round (walls, towers, siege engines built on site, ballistae, escalade, the hero leading the garrison, the horde's leader and grudges), the Holy City's guard, raid or raze, loot and recruits, moving on to the next target, ruins and the refugee camp, survivors settling into camps, camps rising after a wave, growing and joining the next horde of their front, outpost raids, fear, leaders' and heroes' experience, wounds and gear, Sanctity, and the bridge's "unscathed" quest. The local engine keeps the server's key order for what the server stores as jsonb (`LocalStore`), so every battle draws the same random numbers. Two more scenarios are recorded and replayed: `battle-scenario` (a village holds behind its walls, then a horde breaches them with a ram and raids it) and `raze-scenario` (an undefended village is raided, then razed, and its people move to a refuge).
      - [x] **Research, caravans, the vault and the hero's commands:** researching techs (with the server's refusals word for word) and the bonuses they bring, caravans to the Holy City vault or another village and back (escorts, ambushes by camps near the road, what doesn't fit), fetching from the vault, enlarging it, rebuilding a ruined village, and the hero's skills, gear, name and travel between villages. The server test `logistics-scenario.test.ts` records a session with all of these, refusals included, and the client test replays it.
      - [x] **Armies, scouting, sites, settlers and quests:** scouts and their reports; armies sent to support, reinforce, harass, hold a hex, clear a camp or explore a site, with the hero leading; reinforcements rallying to a village under attack; field battles where a horde meets a held hex (ambush, choke points, forts, rivers), and a horde breaking through marching on late; camps stormed and their loot; sites explored, their guardians, and what they give (resources, gear, Ember, scrolls); forts (and bandits taking an abandoned one), roads and bridges; settlers founding a village; and the hero's quests (ambush, scouting, caravan, hoard, ruins). Two scenarios are recorded and replayed: `army-scenario` (scouts, a hero-led army holding the horde's road, a site, a quest, a camp stormed, refusals) and `expansion-scenario` (settlers found a second village, the hero moves there, armies support and reinforce it, a road is built).
      - [x] **Standing orders, the bridge and the end of a run:** standing orders (repeat training, rebuilding outposts, sending surplus to the vault) placed, refused, run every few game minutes and cancelled; donating to the bridge and forging the ritual torc; raising a stage, the lair or site a new stage asks for, Ritual Night's hordes from every front, and the run won (or lost when Sanctity falls to 0), with its summary; a finished run stands still and refuses commands. The scenario tests can jump a world ahead (`set` steps: the bridge's state, the group's Ember), so `endgame-scenario` plays the last stage, Ritual Night and the win.
      - [x] **The inbox:** everything the server tells a player (builds, battles, raids, razes, camps, scouting and settlers, heroes and leaders, research, caravans and ambushes, the bridge, Ritual Night and the run's end), the wave warning before a horde arrives, the daily digest, and marking it read, with the server's wording in English and Serbian. `npm run fixtures` bundles the server's notice table into the app (`client/data/notices.json`) and writes `data/fixtures/notice-vectors.json`, notices as the server renders them, which the client test checks. Every scenario now ends with the player's inbox, and `inbox-scenario` covers the digest and reading.
      - [x] **Play solo:** the start screen's "Play solo" section, there signed in or not and with or without a connection: start a solo world (name, speed, difficulty, hero), continue one, or delete one (a second tap confirms). Solo worlds are saved on the device and read back.
25. [x] **Main menu rework:** research game UI design first: menus of strong mobile and PC strategy games, and what makes them read as modern. Then rebuild the main menu:
    - modern, split into clear compartments: play (continue, new solo world, co-op worlds), profile, settings, help and support;
    - the first action one tap away, and nothing that wastes space.
    - Write the findings and the design in `docs/art-style.md` before building it.
    - **Done:** the findings and the design are in `docs/art-style.md` ("The main menu"). The start screen is now four compartments behind a tab bar (on top on a wide screen, at the bottom in thumb reach on a phone), each with a new icon: **Play** (Continue the world played last, then solo worlds, then co-op: guest sign-in, your worlds, a new world and joining by code; the new-world forms open from a button), **Profile** (rename, sign out, export your data; deleting the account stands apart and asks twice), **Settings** (language and text size) and **Help** (how a run goes, reporting a problem, the server costs and donating, the privacy policy). The world played last is kept on the device (`Session.last_world`).
26. [x] **Sound and music:**
    - sound effects for taps, building, training, battle rounds, horns for hordes, and wins and losses;
    - music: calm themes for the map and the village, a tense one when a horde is near, and one for battles;
    - separate volume sliders for music and effects; everything free to use (CC0 or the like) and listed in the credits.
    - **Done:** a `Sound` autoload with "Music" and "Effects" buses. Music crossfades as the screen changes (`SoundCues`): the map theme on the map and in the menu, the village theme in the village, a war theme while a horde is under an hour from one of your villages or at its gates, the battle theme on the battle map, and the victory or defeat theme when a run ends. Effects: every button taps; building, training, research and claims, caravans and donations, errors, battle rounds (five takes of clashing steel), and a war horn when a horde sets out on one of your villages. The volume sliders are in the menu's Settings and are kept on the device. All CC0 (RandomMind, spring-spring and stumpystrust on OpenGameArt, and Kenney), listed in `client/audio/CREDITS.md` and in the menu's Help.
27. [x] **Balance:** smarter simulator bots (teammates holding strong points, late Ember gathering), many runs per player count and preset, tuning towards a 60–75% win rate on Normal.
    - **Done:**
      - **Matrix runs:** `npm run sim:matrix` plays every player count and preset asked for on fixed map seeds (`--seed` in `npm run sim`), over parallel processes, and prints a table of win rates. Two tunings meet the same maps.
      - **Bots:** they raise walls and towers, go defensive while a horde is coming, and no longer hold back quests while reinforcements are out. Two other tries made them worse and were dropped: a wider reinforcement range (armies far from home stalled quests), and training before building whenever the garrison was short (solo bots never caught up and built nothing else).
      - **Embers:** Story runs stalled at the last stages for want of Svarog's Embers (fewer camps, few lairs, a lair's Ember only a 75% chance). Now a lair rises when a stage opens wanting Embers the group lacks, and a cleared lair always holds one while the bridge lacks one (`ember-scenario` covers it on both engines). Story, 2 players: 1 of 4 won before, 3 of 4 after.
      - **Numbers:** with lairs bringing Embers, Normal won 79% (19 of 24 runs, 1–4 players); Normal's hordes are now 10% bigger (`waveScale` 1.1), and it wins 75% (18 of 24: solo 4/6, 2 players 5/6, 3 players 4/6, 4 players 5/6), at the top of the target.
      - **Caveat:** six runs per player count give a wide margin (about ±35%); a run takes minutes, so these are the honest limits for now. Solo misses are mostly bots stalling on a quest (a site, a choke) rather than losses; losses come late (day 50 and on), on Ritual Night or with the bridge stuck. The closed test (step 28) checks this with people.
28. [x] **Fixes after 0.5.1** (asked for after step 27):
    - Every explanation in the game reads in real time, not game time (speeds, upkeep, food carried, starvation, repeat-training checks, the almanac, run length, the ambush quest). The watchtower's rule stays as it was; its text already read in real time.
    - Report a bug opens in the side sheet, with Send and Cancel. The repeat-training form keeps its numbers on their own rows. The Train tab picks the building from a dropdown of the ones built.
    - Training queue and standing orders grow with the village (§11.2).
    - **Join after the start:** an invite code works while a run is under way; the newcomer's village is founded on free settleable ground away from the others (`joinSite` in `sim/expansion.ts`), with a hero and the group's bonuses, and the group hears of it.
    - **Searching for ruins** (§8.1): scouts sent from the Troops tab; `ruins-scenario` plays it in both engines.
29. [ ] **Closed test:** friends play a full run; fix what they find.

### M0/M1 first tasks
1. Repo skeleton (layout above), TypeScript server with lint/test, Godot project, `data/` with schemas.
2. Hex math library (axial coords, distance, neighbours, A*) in the server; matching rendering helpers in Godot.
3. `scheduled_events` table + world worker with locking + lazy resources.
4. Minimal auth (guest) + create/join world by invite code.
5. Godot: map view, village panel, build queue, timers, WebSocket client.
6. North front: schedule, spawn, march, simple battle, report.
7. Scouting with precision tiers.
8. Deploy to a VPS; play a 2-player slice at 10× speed for a few days.

---

## 15. Open Items / To Verify

- **All numbers marked *(tunable)*** are first guesses to be set by the headless simulator.
- **Order of the One Throne** visual identity and art for the folklore roster: to design with the art pass (the rosters themselves are in `data/enemies.json`).
- **Game title:** "Slavian" is the working title.
