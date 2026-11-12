# Slavian — improvement backlog

A list to pick from, not a plan. Tick what makes sense, strike what doesn't.
Each item has a rough **size** (S: hours, M: a day or two, L: a week or more)
and what it buys. Nothing here is decided; the settled design stays in `PLAN.md`.

Contents:

1. [UI/UX redesign proposal](#1-uiux-redesign-proposal)
2. [UI/UX: single improvements](#2-uiux-single-improvements)
3. [Gameplay](#3-gameplay)
4. [Performance and code health](#4-performance-and-code-health)

---

## 1. UI/UX redesign proposal

### 1.1 What is wrong today

- **One sheet does everything.** A single bottom sheet shows a hex, a village
  (with tabs), an army (with tabs), the hero, research, caravans, orders,
  threats, inbox, chat, the almanac and reports. Where you are depends on
  hidden state (`_panel_mode`, `_tab`, `_view`), and "Back"/"Close" lands in
  different places from different sheets.
- **Icon-only top bar.** Forces, orders, research, hero, messages, almanac,
  settings are unlabeled icons on the wood band. New players have to tap each
  to learn it; on a phone tooltips never show.
- **Too much unneeded text.** A lot of the text can be shorter to increase
  overview and lower the clutter. A lot of things don't need to be full
  sentences.
- **Text first, pictures second.** Most sheets are paragraphs of prose with
  buttons underneath. Costs, times and effects are inside sentences, so
  comparing two buildings or two units means reading both in full.
- **Long scrolling forms.** Sending troops, a caravan or a bounty is one long
  column of number boxes. The confirm button is at the bottom, often off screen.
- **Map picking is modal and fragile.** "Tap a hex" modes shrink the sheet and
  wait; a stray tap or a live update can cancel them (the v0.14.0 Move bug).
- **Little feedback.** An action succeeds silently or writes one line into a
  status label that is easy to miss. Nothing animates when resources are spent,
  a build starts or troops leave.
- **Everything refreshes at once.** A live update rebuilds the whole sheet:
  scroll position and half-typed numbers can be lost.

### 1.2 Principles for the redesign

1. **Three taps to anything, one tap back.** Every screen has one way in and
   the same way out.
2. **Show, then tell.** Icon + number first; prose only behind an "i".
3. **The map is the game.** Sheets are small by default and never cover the
   thing you are deciding about.
4. **One primary action per screen**, always in the same place (bottom, in
   thumb reach), always visible.
5. **Nothing is lost.** Drafts, scroll and selection survive live updates.

### 1.3 Navigation

- [x] **Bottom navigation bar with five labeled tabs** (L): **Map · Village ·
  Army · Hero · More**. Replaces the view toggle and most top-bar icons.
  "More" holds research, orders, caravans/market, almanac, settings, report a
  bug. Badges on tabs (idle queue, unread, army in battle).
- [x] **Slim top bar** (M): village switcher on the left, the four resources
  in the middle, messages bell on the right. One row, no title, no live label
  (show a thin red line only while offline).
- [x] **Threat ribbon** (S): the next horde as a ribbon under the top bar with
  a countdown; tap centres the map on it. Hidden when nothing threatens.
- [ ] **Real back stack** (M): every screen pushes onto a stack; the Android
  back button and a single "←" pop it. No more per-sheet Close buttons.
  *(Partly done: the phone's back button and Escape now step sheet → map →
  worlds.)*
- [ ] **Village switcher as a carousel** (S): swipe left/right on the village
  name to go to the next village; long-press for the list.

### 1.4 Screens

- [ ] *(partly done: bare hexes open a short peek sheet)* **Map** (L): tap a hex → a small *peek card* (name, owner, 2–3 key
  facts, 1–3 action chips). Swipe the card up for the full sheet. Selecting
  your army shows its reachable actions as chips on the map itself
  ("Move", "Attack", "Join") rather than in a sheet.
- [ ] *(partly done: building cards, red costs, one Upgrade button)* **Village** (L): the picture of the village is the menu. Tap a plot →
  a card with level, what the next level gives (as before → after numbers),
  cost chips coloured red when you can't pay, and one big **Upgrade** button.
  Empty plot → a grid of building cards (icon, name, one-line effect, cost),
  not a text list. The queue is a strip of chips along the bottom with
  countdowns; drag to reorder, tap to cancel.
- [ ] *(partly done: unit cards, Max, red costs)* **Recruit** (M): one grid of unit cards per building; each card has the
  portrait, attack/defence/speed/upkeep as four icons, and a stepper
  (−/+ and "max"). The training queue sits in the same strip as builds.
- [ ] *(partly done: troops as pictures with counts, army cards)* **Army** (M): header with banner, strength bar, supply bar, stance chip.
  Under it the troops as a row of unit portraits with counts. Actions as a
  fixed bar: **Move · Stance · Supply · More**. Settings and leaders go
  behind "More".
- [ ] *(partly done: Send sits at the top of the troops form, always in sight)* **Send troops / caravan / bounty as a 3-step wizard** (M): *What*
  (steppers with "all"/"half" chips) → *Where* (tap the map, with the route,
  travel time and grain cost drawn live) → *Confirm* (one summary card).
  The confirm button is pinned to the bottom the whole time.
- [ ] *(partly done: XP bar, skills as cards with rank pips, gear slots as cards)* **Hero** (M): paper-doll with gear slots, skill tree as nodes rather
  than a list, quests as cards with reward icons.
- [ ] *(partly done: filter chips, notices as cards)* **Messages** (M): one inbox with filter chips (All · Battles · Economy ·
  Events · Chat). Battle reports open as a result card first (won/lost,
  losses, loot) with "Watch the battle" for the round-by-round replay.
- [x] **Threats** (S): a timeline — hordes as beads on a line by arrival time,
  coloured by front, with what you know from scouting.
- [ ] **Main menu** (M): a painted backdrop, "Continue" as the one big button
  (last world), then Solo / Multiplayer / Achievements / Settings.

### 1.5 Visual language

- [ ] **Design tokens** (M): one file with the spacing scale (4/8/12/16/24),
  three text sizes, the colour roles (surface, on-surface, accent, good,
  warning, danger) and corner radius. Every screen draws from it.
- [x] **Card component** (M): parchment card with a carved-wood header, one
  shadow, one radius. Replaces today's mix of panels, rules and plain labels.
- [ ] **Three button kinds only** (S): primary (filled, madder red), secondary
  (outlined), quiet (text). At least 48 dp tall. Destructive actions always
  ask via a hold-to-confirm rather than a second "Sure?" tap.
- [ ] *(partly done: attack, defense, health, speed icons for unit stats)* **Icon set pass** (M): one stroke weight, one size grid; every resource,
  stat and action gets an icon so numbers can stand without words.
- [ ] **Resource chips** (S): `icon 120` chips used everywhere a cost or loot
  is shown; red when short, with the shortfall on tap.
- [ ] *(partly done: sheets fade in, toasts)* **Motion** (M): sheets slide, cards fade in, resource numbers count up
  or down, a built plot "pops", an army leaving draws its route. 150–250 ms,
  with a "reduce motion" setting.
- [ ] **Typography** (S): a display face with Slavic character for headings,
  a clean humanist sans for numbers and body; tabular digits for timers.
- [x] **Dark "night" theme** (M): follows the device, or the in-game hour.

### 1.6 Feedback and safety

- [x] **Toasts** (S): every command answers with a short toast ("Barracks
  queued · 12 min"); errors shake the button and say what is missing.
- [ ] **Undo for five seconds** (M) on cheap reversible actions (queue a build,
  send a caravan) in place of confirmation dialogs.
- [ ] **Disabled buttons explain themselves** (S): tap a greyed button to see
  why ("needs Barracks 3", "40 stone short — ready in 6 min").
- [ ] **Keep state across live updates** (M): update the numbers in place;
  never rebuild a sheet the player is typing or scrolling in.
- [x] **Haptics** (S) on confirm, error, battle start, horde horn.

### 1.7 Onboarding and help

- [ ] **Guided first ten minutes** (M): spotlight the control to press, one
  sentence each, skippable; replaces reading the quest card.
- [x] **"What next?" button** (M): one suggestion from the game's state (idle
  queue, full store, unspent skill point, unscouted horde).
- [ ] **Almanac search and deep links** (S): every "i" opens the right
  almanac entry; the almanac gets a search box.

### 1.8 Accessibility

- [ ] Text size setting (S) · colour-blind-safe side colours with shapes as
  well as colour (S) · one-handed mode that mirrors the action bar (S) ·
  minimum 48 dp targets everywhere (S) · screen-reader labels on icon
  buttons (M).

### 1.9 Suggested order

1. Tokens, card, buttons, resource chips (the kit) — no screen changes yet.
2. Bottom navigation, slim top bar, back stack.
3. Village screen and recruit grid.
4. Map peek card, army action bar, the send wizard.
5. Messages, hero, threats timeline.
6. Motion, haptics, night theme, onboarding.

Splitting `game_screen.gd` (6,400 lines) into one script per screen should
happen with step 2: each later step then touches one small file.

---

## 2. UI/UX: single improvements

Things worth doing even without the redesign.

- [ ] Label the top-bar icons, or show a first-run legend (S).
- [ ] Pin the confirm button of every form to the bottom of the sheet (S).
- [ ] "All", "Half", "None" chips next to every unit and resource stepper (S).
- [ ] Show travel time, grain cost and arrival clock time while picking a
  destination, before confirming (S).
- [ ] Draw the planned route on the map while picking a destination (M).
- [ ] Idle indicators: a dot on a village with an empty build queue or a
  full store; a dot on an army with no orders (S).
- [ ] "Time until full" under each resource instead of only the rate (S).
- [ ] Build queue: show the clock time each item finishes, not only the
  duration (S).
- [ ] Long-press a plot/unit for its stats card instead of a separate info
  button (S).
- [ ] Remember the last tab per village and per army (S).
- [ ] Pinch-zoom limits and a "home" button that recentres on your village (S).
- [ ] Map filters: toggle roads, routes, fear, fronts, allies' armies (M).
- [ ] Mini-map or edge arrows pointing to hordes and your armies off screen (M).
- [ ] Battle report: a one-line verdict and loss bars at the top; the round
  log folded by default (S).
- [ ] Notifications grouped by kind with "mark all read" per group (S).
- [ ] Chat: unread divider, tap a hex coordinate in a message to jump there (S).
- [ ] Settings: language, sound, music, text size, reduce motion, orientation,
  notifications — one screen, reachable from the menu and in game (S).
- [ ] Empty states with a hint and a button ("No armies yet — raise one in
  the Barracks") instead of blank lists (S).
- [ ] Loading skeletons when opening a world instead of a frozen menu (S).
- [ ] Reconnect quietly; show "offline" only after a few seconds (S).
- [ ] Landscape: sheet docks to the right as a side panel (M).
- [ ] Tablet layout: map and sheet side by side (M).

---

## 3. Gameplay

### 3.1 Pacing and the check-in loop

- [ ] **Daily goals** (M): three small tasks a day (train 20, clear a camp,
  send a caravan) with a modest reward — a reason for the 2–5 minute check-in.
- [ ] **Offline summary** (S): on opening, one card: what was built, trained,
  fought and lost since you were last here.
- [ ] **Queue more, wait less** (S): let the first two queue slots be free at
  Hall 1 so new players are never stuck after one tap.
- [ ] **Speed-ups from play, not pay** (M): "boons" earned from sites and
  quests that finish a build or a march early.
- [ ] **Catch-up for late joiners** (M): a player who joins a running world
  starts with stores and levels scaled to the group's average.

### 3.2 Economy

- [ ] **Village specialisation** (M): pick one focus per village (granary
  town, forge town, garrison town) at Hall 5 for a strong bonus and a
  matching weakness.
- [ ] **Overflow** (S): a full store sends a share of the surplus to the
  vault instead of wasting it.
- [ ] **Market prices that move** (M): trade rates drift with what the group
  buys and sells.
- [ ] **Seasons** (L): a four-week year; winter cuts grain and slows marches,
  rivers freeze and can be crossed, spring floods them.
- [ ] **Trade routes with allies** (M): a standing caravan between two
  players' villages that pays both.

### 3.3 Military

- [ ] **Formations** (M): pick front/flank/reserve per army; counters archer
  and cavalry mixes without new units.
- [ ] **Veterancy** (M): units that survive battles gain a rank (+5%/+10%);
  losing veterans hurts, so retreat matters.
- [ ] **Retreat rule** (S): a threshold per army ("fall back at 40% losses").
- [ ] **Battle preview** (M): before attacking, a rough odds line from what
  scouts know ("likely win, heavy losses").
- [ ] **Siege phase** (M): walls must be breached (rams, scorpions) before
  the garrison fights at full strength — gives siege units a clear job.
- [ ] **Joint attacks** (M): armies of several players arriving within a
  window fight as one battle with a combined-arms bonus.
- [ ] **Named units and trophies** (S): an army that wins big earns a title
  shown on its banner.

### 3.4 Threats

- [ ] **Horde variety** (M): each front gets one special behaviour (raiders
  that avoid walls and burn outposts; a slow siege host; a swarm that splits).
- [ ] **Boss hordes with a telegraphed weakness** (M): scouting reveals it
  ("fears fire", "slow in forest").
- [ ] **Mid-run crisis events** (M): plague, drought, a traitor village — a
  group decision with a trade-off rather than a plain penalty.
- [ ] **Difficulty that answers the group** (S): scale wave size to recent
  wins and losses within a band, so a bad day isn't the end of a run.
- [ ] **Counter-raids** (M): destroy a camp and the front it fed sends
  smaller waves for a while.

### 3.5 Heroes, clans, progression

- [ ] **Hero abilities with a cooldown** (M): one active skill per hero (rally,
  forced march, ambush) used from the army bar.
- [ ] **Gear sets** (S): two or three pieces of a set give a bonus.
- [ ] **Clan quest line** (M): each clan has a short story across a run with
  a unique reward.
- [ ] **Account progression** (M): achievements unlock cosmetic banners,
  village skins and starting options — never power.
- [ ] **Run modifiers** (M): optional "oaths" at world creation (no walls,
  double hordes, one village) for more score.
- [ ] **Leaderboard and run history** (M): score per run, best per clan/hero.

### 3.6 Co-op

- [ ] **Pings on the map** (S): "defend here", "attack this", "send grain" —
  quicker than chat on a phone.
- [ ] **Shared plan board** (M): pin up to five goals for the group; anyone
  can tick them.
- [ ] **Gifting** (S): send resources or troops to an ally in two taps from
  their village's peek card.
- [ ] **Roles** (M): quartermaster/marshal/scout — small bonuses that nudge
  players to split the work.
- [ ] **Vote on the bridge ritual and other group choices** (S).

### 3.7 Solo

- [ ] **AI allies in solo** (L): one or two bot villages that trade, ask for
  help and send help, so solo teaches the co-op game.
- [ ] **Scenarios** (M): short hand-made starts (hold the ford for five days).
- [ ] **Pause and speed controls in solo** (S).

---

## 4. Performance and code health

### 4.1 Done in this change

- Auth and membership checks are single statements (no `BEGIN`/`COMMIT`
  around them), and a session's `last_used_at` is written once an hour rather
  than on every request: 2–4 fewer round trips on every call.
- The world view reads each shared source once (`memoReads`): opening a
  world went from 51 queries to 39, and more in worlds with several heroes.
- Reading the vault no longer writes on every read.
- Live updates: a burst of the same news for a world is read once, and each
  message is turned to JSON once for all subscribers.
- Map: a battle's swords are drawn on a layer of their own; the whole map is
  no longer redrawn every frame while any battle is on.
- Game screen: several live updates in one frame rebuild the sheet once; the
  resource rate labels are no longer re-laid-out four times a second.

### 4.2 Still open

- [ ] **Split `game_screen.gd`** (L) — one script per screen. The largest
  single cost to every UI change.
- [ ] **Update sheets in place** (L): bind labels to state so a live update
  changes numbers rather than rebuilding hundreds of controls.
- [ ] **Scheduler: fewer round trips per event** (M): each event costs about
  five statements of bookkeeping (next event, savepoint, mark done, release,
  re-read the world). Batch the mark-done with the release, and re-read the
  world only when a handler says it changed it.
- [ ] **World view in fewer statements** (M): the ~35 remaining reads are
  independent; fold the small per-world lists into one query, or keep a
  read-only snapshot connection per request and pipeline them.
- [ ] **Smaller live messages** (M): `world` events resend the whole world
  (terrain included). Send only the part that changed; send terrain once.
- [ ] **Cache terrain in memory** (S): a world's terrain never changes after
  the start, yet is read on most commands.
- [ ] **`/v1/data` with an ETag** (S): 95 KB serialised on every session
  start; cache it on the device by version.
- [ ] **Map culling** (M): draw only what the camera sees; matters once maps
  or armies grow.
- [ ] **Map layers** (M): roads/rivers (static), settlements (rare changes)
  and moving things (every tick) as separate canvas items, so a marching
  army doesn't redraw the rivers.
- [ ] **Texture atlas for map art** (S): fewer draw calls on low-end phones.
- [ ] **Scheduler: worlds in parallel** (S): worlds are independent; drain a
  few at once instead of one after another.
- [ ] **Indexes review with real data** (S): run `EXPLAIN` over the world
  view's queries on the production database once a few long runs exist.
- [ ] **APK size** (S): the release is about 98 MB; check for uncompressed
  art, unused export templates and debug symbols.
