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
| Q4 | Connectivity | Online-only. Cached last-known state viewable offline; orders need a connection. |
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
| Q25 | Heroes | One per player, leads one army, skill tree, gear from sites, wounded instead of killed. |
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
  - Hold a choke point for a full battle.
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
- Godot 2D, stylized flat illustration. Hex tiles and buildings as sprites.
- Slavic ornament (embroidery patterns, carved-wood motifs) in UI frames.
- Muted earth palette, bright accents only for threats and actions.
- Placeholder (stock / AI-assisted) art until M5.
- Portrait-first phone layout. Map pan/zoom with one-finger drag and pinch.

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
| **M5 — Beta** | Ready for friends | Closed test, balance passes, English + Serbian (Latin) localization, accessibility pass, final-ish art, donation button + cost slider, privacy policy, backups/monitoring. |
| **M6 — Launch** | Play Store | Android release. iOS and desktop afterwards. |

### M0 status
- [x] Repo skeleton: `server/`, `client/`, `data/`, `ops/`, CI workflow.
- [x] Hex math in TypeScript and GDScript, both checked against `data/fixtures/hex-vectors.json`. A* pathfinding on the server.
- [x] Scheduler prototype: `scheduled_events`, one writer per world (Postgres advisory locks), lazy resource ledger, build queue command that catches the world up before acting, failed events isolated. Integration tests cover concurrency, late workers and failures.
- [x] Godot map spike: placeholder world generator (fronts per group size, edge belt, start ring), hex rendering, touch pan / pinch zoom / tap select, Android export preset.
- [ ] Run the spike on a physical Android phone and measure frame rate. If drawing ~800 hexes with `_draw()` is slow, switch to a batched mesh or `TileMapLayer`.

### M1 breakdown (each step is its own PR)
1. [x] **Online foundation:** HTTP + WebSocket API, guest accounts, worlds with invite codes and a lobby, server-side map generation on start (player count decides size and fronts), a village per player, build queue over the API, live updates (Postgres NOTIFY → WebSocket). Client: sign-in, worlds list, create/join, lobby, map from the server, village panel with live resources and build queue. Docker image + compose.
2. [x] **Units:** barracks and scout lodge, training queue (batches train one unit after another, counted lazily), garrison, grain upkeep from the moment units are drafted. Spearman, archer, horseman, scout (`data/units.json`). Starving troops deserting comes later; for now grain just floors at zero.
3. [x] **North front waves:** waves are announced ahead (front, spawn time, threat level; composition hidden), the first after the one-week grace period and then every 2–3 days, growing with each wave and with player count (`data/waves.json`, `data/enemies.json`). A wave spawns in the dark forest / ice, marches to the nearest village by path cost at its slowest unit's pace, and (until battles exist) camps at the gates for the rampage time, then disperses. Client: threat banner, threats timeline, hordes and their route on the map. Only the North front is enabled for now; quiet hours come with M3.
4. [x] **Scouting:** send scouts from your village at a wave (gathering in its spawn zone, marching, or at the gates); they travel by path at scout speed, each survives with the front's survival chance, and the survivors' report (shared with the group) is none / rough (size ±30%, main unit) / detailed (size ±10%, every unit with a range) / exact (6+ survivors), per `data/scouting.json`. Survivors walk home; scouts away still eat, the dead stop. Enemy stance and planned target join the report once they exist (step 5).
5. [x] **Battles:** a horde reaching a village fights its garrison in rounds (every 15 game-minutes, up to 12). Damage uses attack, defense, family counters (infantry > cavalry > archers > infantry), stances (Defensive / Balanced / Offensive / Hold the Line with attack, defense and retreat thresholds), stance matchups and a home bonus, with seeded variance (`data/battle.json`). A side breaks at its stance's loss share; undecided after the last round, the horde withdraws. Defended → the wave is beaten; raided → the horde takes up to 30% of stores (scaled by its survivors) and leaves. Waves have a stance by front temperament, revealed by detailed/exact scout reports. Battle reports are shared with the group. Reinforcements, field setups, raid-vs-raze and walls come in M3.
6. [ ] **Playtest:** 2 players at 10× for a few days. Setup ready (`docs/playtest.md`): server in Docker on the host's computer, database on Neon, public HTTPS through a Cloudflare quick tunnel; the app can change server address without signing out. A VPS replaces the computer later (M5).

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
3. [ ] **All fronts and factions:** East (nomads) and South/West (Order of the One Throne) rosters per group size, faction personalities, the folklore monster roster.
4. [ ] **Horde AI:** fear-weighted targeting, raid vs raze by reasoning, ruins and refugee camps with rebuilding, the rampage clock (survivors become a bandit camp), fighting at the Holy City.
5. [ ] **Camps and lairs:** spawn at the end of each wave, grow and feed the next wave, cleared by armies for loot (resources, gear, Svarog's Ember); caravan interception and escorts.
6. [ ] **Quiet hours and difficulty:** the group's quiet window for wave arrivals and battle starts; difficulty presets and group-power scaling.

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

- **Interslavic clan names:** verify spelling and the "Rod + genitive" form (Rod Jelena, Rod Rysa, Rod Medvěda, Rod Bobra, Rod Sokola, Rod Volka).
- **All numbers marked *(tunable)*** are first guesses to be set by the headless simulator.
- **Monster roster** from Slavic folklore and **Order of the One Throne** visual identity: to design in M3.
- **Game title:** "Slavian" is the working title.
