# 13. Events and raids beyond the edge

[← Scouting, exploration and expansion](12-scouting-and-expansion.md) · [Index](README.md) · Next: [The Kalinov Bridge and the endgame →](14-bridge-and-endgame.md)

## Daily map events

**Every 24 game hours** from the second day of a run, an event rises.

- **Where.** On open passable land 3–7 hexes from one of the players'
  villages.
- **How long.** It lasts **48 game hours**, unless an army is already on its
  way to it.
- **Which kind.** Kinds are picked by weight. The rare ones (the ritual, the
  mountain city) come about 1 time in 35.

| Kind | Weight |
|---|---|
| Captives | 1 |
| Hard ruin | 1 |
| Shipyard | 1 |
| Cultist ritual | 0.09 |
| Mountain city | 0.09 |

### Bounty and failure

- **The bounty.** Every event done pays 400 wood, 400 stone, 400 grain and
  200 iron, +25% for every day of the run after the first. It goes to the
  first village of the player who did it. A finished boat or a built mountain
  city pays every member.
- **Failure.** An event left undone when its time is up adds **+0.2 hatred**
  to the front of the land it rose in ([page 9](09-hordes-and-threats.md#hatred)).

### Captives

- **The camp.** A camp of the land's front holds captives: 6 guards, +25% for
  every day of the run after the first.
- **Freeing them** means clearing the camp. With a 50% chance, 4 (+1 a day)
  Spearmen, Archers or Axe Levies join the army that freed them. Otherwise
  150 / 150 / 150 / 100 (+25% a day) ride home with it.
- **A tame camp.** The captives' camp doesn't grow, join hordes or ambush
  caravans.

### Hard ruins

A **hard ruin** is an ancient site ([page 12](12-scouting-and-expansion.md#ancient-sites))
watched by **3×** its usual guardians, whose resources are worth **2×** as
much.

### Shipyards and river boats

A **shipyard** rises on a river bank. It is never on a river (or a lake it
reaches) that already has a shipyard.

1. **Paying.** Any player sends resources from a village within 8 hexes (or by
   caravan) until **900 wood, 300 stone, 300 grain and 150 iron** are paid. If
   nobody has paid anything when its time is up, it goes.
2. **Building.** The boat then takes **24 game hours**.
3. **Raids.** Every **2 game hours** while it builds, raiders strike it: 5 of
   the land's front, more each day, in an offensive stance.
   - **Defending it.** Armies standing on its hex defend it one after
     another.
   - **Failing to.** If they don't drive the raiders off, 6 hours of work
     are lost.
   - **Burned three times,** the shipyard is lost and the event fails.
4. **The boat.** Once done, travel along that river is **3× as fast** for good,
   including lakes the river reaches ([page 2](02-map-and-movement.md#river-boats)).

### The cultist ritual

Rare.

- **The camp.** Cultists of Černobog camp on the map: 16 guards of the land's
  front, more each day.
- **The ritual.** Their ritual ends **36 game hours** after it begins. Every
  soldier of yours who falls fighting them brings the end **20 game minutes
  closer**.
- **Clearing the camp** stops it, for the event's bounty.
- **If it ends,** the **Avatar of Černobog** rises where they stood, and
  marches on the villages like a horde of the camp's front:

| Avatar of Černobog | |
|---|---|
| Attack / defense / health | 2,500 / 100 / 6,000 |
| Speed | 3 |
| Siege | 60 a round |

- **Slaying the Avatar** brings **4×** the bounty to every member.
- **Achievements.** Breaking the circle, seeing the Avatar rise and slaying it
  each have a hidden achievement.

### The mountain city

Rare. A **neutral city** rises inside a mountain (a mountain hex beside
passable land).

- **The hex** becomes Mountain City land that armies can enter and hold.
- **Paying.** It is paid for like a shipyard: **900 wood, 1,500 stone,
  600 grain and 600 iron**, from villages within 8 hexes or by caravan.
- **Building.** It takes **36 game hours**.
- **Raids.** Every **3 game hours**, 8 monsters from under the mountain (the
  North's, more each day) strike it. Armies standing there defend it. Struck
  down 3 times, the city is lost and the hex is mountain again. The same
  happens if nobody pays before the event ends.

Once built, it stands for good:
- **Production.** Every member's villages produce **+10% of every resource**.
  Each mountain city adds its own +10%.
- **Trade.** A caravan that brings it grain brings back **1 stone for each
  grain**.
- **Supply.** It is a **neutral supply point**: any player's caravans fill its
  grain store, and any army standing there draws on it.
- **Safe.** Hordes never come into the mountains, so none burns it, and no
  bandits take it.

## Raids beyond the edge

An army can march to the map's edge on a front's side and **raid into the
enemy's lands**:

- **The road in.** It marches to the nearest passable hex of that front on the
  map's last ring. Then it fights its way in: `depth` field battles (1 to 3),
  then the siege of the front's **stronghold**.
- **The pace.** One battle every **3 game hours**, the first one stage after
  it reaches the edge.

| Front | Fields (one per stage, in a seeded order) | Stronghold |
|---|---|---|
| North | Frozen Marsh, Dark Thicket, Bone Hills | Monster Lair |
| East | Open Steppe, River Ford, Kurgan Ridge | Nomad Encampment |
| South | Vineyard Terraces, Pilgrim Road, Olive Groves | Fortress of the Order |
| West | Mill Meadows, Abbey Orchards, Stone Bridge | Templar Keep |

- **Fields.** Each field scales each side's attack and defense by up to ±15%.
  Field enemies fight Balanced.
- **Enemy size.** 12 × 1.3^(stage − 1) × 1.039^(waves so far), more for bigger
  groups.
- **The stronghold** has 1.8× that, fights Defensive from behind its walls
  (home bonus, +40% defense), and **battering rams** take a quarter of its
  walls off each.
- **Grain.** The army eats its own grain all the way: only what its military
  reserve and wagons carry.

**Spoils.** Each battle won takes:
- **Loot per kill:** 14 wood, 10 stone, 16 grain and 8 iron per enemy killed
  (×the front's greed).
- **The stronghold** adds 500 / 400 / 500 / 300 when sacked.
- **Carrying.** All of it as far as the army can carry: 30 per fighting unit,
  400 per military caravan.

**Raiding the North** brings only 30% of that in resources, but every battle
won has a chance at a rare find:

| Find | Chance per battle (stronghold ×3) |
|---|---|
| Hero gear | 12% |
| A lore scroll the group hasn't found | 8% |
| A Svarog's Ember | 8% |

- **Hatred.** Every battle won adds **+0.05 hatred** to that front, and
  sacking the stronghold +0.15 more.
- **Going home.** A raid beaten in any battle, or left with no one, comes home
  with what it carries.
- **The Eye of Veles.** The bridge's fourth stage needs a raid on the North to
  its full depth with the stronghold sacked ([page 14](14-bridge-and-endgame.md#the-five-stages)).

## Strikes on a gathering horde

- **The strike.** An army can march to the edge on the side of a **scheduled**
  horde and attack its **Horde Encampment** before it sets out. The encampment
  fights from behind walls, like a stronghold.
- **How much is there.** Only the part of the horde gathered by then fights:
  all of it at the hour it sets out, down to **35%** if the strike lands **24
  game hours** or more before.
- **For good.** Troops killed are gone from the horde for good.
- **Hatred.** Win or lose, the front's hatred rises by **+0.6**. Its next horde
  takes it all as extra attack and defense.
- **Going home.** The army comes home after the one battle.
