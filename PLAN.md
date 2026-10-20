# Slavian — Game Design & Implementation Plan

> Working title: **Slavian**. A cooperative, PvE, hex-map strategy game for busy adults.
> Mobile-first (Android), cross-platform later. Players give orders in short check-ins; everything executes over real time on the server.

This plan is the outcome of a design interview. Each decision below is settled unless marked **(to verify)** or **(tunable)**. Numbers marked *(tunable)* are starting values that live in data files and get rebalanced.

---

## 1. Vision

The last bastion of Slavic faith and culture is the **Holy City**. A small group of friends (2–6, or solo) found villages around it, grow them, claim the land and prepare for the hordes coming from every direction. They win by building the **Kalinov Bridge** between the realms in the Holy City before the city falls.

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
| **Kalinov Bridge** | The win objective: a 5-stage project in the Holy City. Named after the mythic bridge over the Smorodina river between Yav (the living world) and Nav (the other realm). |
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
- Starting buildings *(tunable)*: Elder's Hall (main building), Granary, Storehouse, Barracks, Wall (Palisade), Marketplace/Caravan Yard, Scout Lodge, Academy, Shrine, Hero's Hall, Settlers' Lodge, Workshop. Plus clan-unique buildings.
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
- **Standing orders:** repeat training, auto-rebuild after raid/raze, reinforcement rules, auto-caravan surplus to the vault above a threshold.

### 11.3 Notifications (Q23)
- **Push only for:** wave arriving within 6 h, a village/outpost under attack, big build finished, teammate request/delegation.
- Everything else goes into **one daily digest**.
- Respect the device's and the group's quiet hours.

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
4. [x] **Roads:** players build roads between neighbouring hexes within 4 hexes of their village (`POST /v1/villages/:id/roads`, not across an unbridged river, half a game hour). Moving along a road costs half the terrain (`field.road.factor`) for armies, caravans, settlers, scouts, heroes and the human hordes, whose routes now prefer them; the Monsters of the North keep off them. Drawn on the map as tracks; the hex panel offers a road towards each neighbour.
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
21. [ ] **Hero roster:** at the start of a run each player picks one of several heroes (`data/heroes.json`), for example a warrior prince, a forest huntress, a wise volkhv, a merchant rider and a shieldmaiden. Each has:
    - strengths and weaknesses (stats that differ by hero, such as attack, defense, speed and command);
    - one or two special traits or abilities of their own (a rallying cry, tracking that reveals hordes earlier, rites that heal the wounded, better trade);
    - a painted portrait (art ids `hero/<id>`), shown in the pick screen, the hero panel and battle reports.
    - Heroes in the same group are different heroes.
22. [ ] **Hero quests:** the hero can head out on quests that take real time, with risk and experience:
    - **Delay the enemy:** ambush a horde's road or burn its camp, so the next wave sets out later.
    - **Reveal:** scout a front far ahead and learn the next waves' size and makeup.
    - **Retrieve:** bring back gear or resources (lost caravans, a smith's hoard).
    - **Explore ruins:** search ancient sites and forgotten ruins in person, faster and with better finds than scouts.
    - Quests appear on the map from the world's seed and from events. A hero away on a quest doesn't lead the garrison, and can come back wounded.
23. [ ] **How to play, made visible:** the getting-started chain (step M4 6) exists, but it is easy to miss: it is three plain lines in the map's village panel, and only there. It doesn't show how to do each step, and its reward lands silently in the first village, so it isn't clear there is one or how to get it. Rework it:
    - **Visible:** a quest card that is always on screen (map and village view) while the chain is open, with the step, its progress ("2 of 6") and the reward in icons. It can be folded away but not lost, and it pulses when a step is ready to claim.
    - **How:** each step says exactly what to tap, with a **Show me** button that points at the real control (an arrow or highlight over the building plot, the Troops tab, the outpost hex) and walks through it.
    - **Claim:** a finished step turns into a **Claim** button, and the reward flies into the resource bar with a sound. Nothing is credited silently.
    - **Quick start:** rewards big enough to speed the first hour, plus a final reward for finishing the chain.
    - **First run:** a short welcome card says what the run is about (hold out, build the bridge) and points at the quest card. It can be skipped, and played again from the menu. The almanac links each topic.
24. [ ] **Local single player** (asked for after step 18): a solo world runs entirely in the app, with no calls to the server.
    - **How:** the rules, the scheduler and the battles are ported to GDScript as an in-app local server (`client/scripts/local/`). It answers the same API calls the client makes today, so the screens don't change. Worlds are saved on the device.
    - **Co-op** keeps the TypeScript server. Both sides run the same shared fixtures (`data/fixtures/`), as the hex math already does, so the two rule sets stay in step.
    - **Order:** data and the sim core (resources, building, training), then the scheduler and catch-up, waves, hordes and battles, then the rest (outposts, caravans, research, heroes, sites, the bridge), each with its fixtures.
25. [ ] **Main menu rework:** research game UI design first: menus of strong mobile and PC strategy games, and what makes them read as modern. Then rebuild the main menu:
    - modern, split into clear compartments: play (continue, new solo world, co-op worlds), profile, settings, help and support;
    - the first action one tap away, and nothing that wastes space.
    - Write the findings and the design in `docs/art-style.md` before building it.
26. [ ] **Sound and music:**
    - sound effects for taps, building, training, battle rounds, horns for hordes, and wins and losses;
    - music: calm themes for the map and the village, a tense one when a horde is near, and one for battles;
    - separate volume sliders for music and effects; everything free to use (CC0 or the like) and listed in the credits.
27. [ ] **Balance:** smarter simulator bots (teammates holding strong points, late Ember gathering), many runs per player count and preset, tuning towards a 60–75% win rate on Normal.
28. [ ] **Closed test:** friends play a full run; fix what they find.

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
