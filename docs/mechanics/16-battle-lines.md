# 16. Battle lines and maneuvers

[← Player against player](15-player-vs-player.md) · [Index](README.md)

Every battle is fought in lines. Numbers alone don't win it: the line has a
width, and a larger army must maneuver to bring its surplus to bear. The
numbers here are in `data/battle.json` (`lines`).

## The line

**The smaller army sets the width.** Infantry forms the line, cavalry stands
on its flanks. The larger side fights with only as many troops as the
smaller side has; the rest wait behind. Example: 100 against 25 means the
100 strike with a quarter of their strength. As their front ranks fall, the
reserve steps up.

**Round 1 is the opening volley.** Only archers shoot, on both sides, and
only at the enemy's infantry (at anyone if it has none). Heroes, generals,
infantry and cavalry strike from round 2. An [ambush](08-armies-and-field.md#field-setups)
skips the volley: the ambushers fall on the horde at once.

## Maneuvers

From round 2, the larger side may maneuver to bring its surplus (the troops
beyond the smaller side's number) into the fight.

| Maneuver | Needs | Payoff |
|---|---|---|
| **Flank** | On flat land (with or without woods): cavalry at least 1.5× the enemy's. On hills (with or without woods): infantry 1.5× the enemy's | The surplus strikes in full and takes only half the blows aimed at it |
| **Pincer** (double envelopment) | A commander (below), and on flat land cavalry 2× the enemy's or cavalry and infantry together 2.2× theirs; on hills the same with infantry first. No mountain, river or lake beside the battle's hex | The surplus strikes at 200% and takes half the blows |
| **Encircle** | 3× the enemy's troops of every kind together | Every unit strikes at 200% and takes a quarter of the blows |

Example (flank): 20 infantry and 30 cavalry against 20 and 20 on plains. 40
fight in the line; the 10 beyond it strike in full. The attackers deal
(40 + 10) / 50 = 100% of their strength and take (40 + 0.5 × 10) / 50 = 90%
of the blows.

**The pincer needs a commander:** a general of level 5, or a hero with
Battle Fury 5, or on flat land Horse Lord 3, or on hills Spearhead 3. A
horde needs a leader of level 5.

**The best maneuver is taken, up to the side's cap.** Each army and each
village garrison chooses how far it goes: *Hold the line* (no maneuver),
*Flank*, *Pincer* or *Encircle* (the default). Set it on the army's sheet
(also mid-battle) or under the village's stance. A field battle's holders
follow the first army there; a village follows its garrison's choice.
Hordes always go as far as they can.

**Nobody maneuvers** behind standing walls (a siege, a raid's stronghold)
or at a bridge.

## Breakthrough

A maneuver is a risk. If the smaller side kills enough of the surplus that
the larger side no longer meets the maneuver's need (counted against the
smaller side's numbers when the maneuver began), it **breaks through**:
- The side that broke through strikes at the maneuver's payoff **+50
  points** and takes its share of blows: after a flank 150% and half the
  blows, after a pincer or an encirclement 250% (and half, or a quarter, of
  the blows).
- The larger side loses its maneuver and can't maneuver again in this
  battle.
- **Help that arrives later shares in it only in part.** The bonus is
  scaled by the share of the side's troops that were there when the
  maneuver began: sending fresh troops into a breakthrough doesn't multiply
  them.

If the smaller side grows instead (reinforcements arrive and the ratio is no
longer met), the maneuver simply ends: no breakthrough.

## Shield Bearer

A side led by a hero with **Shield Bearer 5**:
- **Keeps its flank** through a breakthrough. The enemy still gets its
  breakthrough bonus.
- **Closes ranks when outmaneuvered.** When the enemy flanks, closes a
  pincer or encircles it, it takes 75% of the blows. Every army fighting
  beside it shares this. After it breaks through, it keeps the 75% on top of
  the breakthrough.

## Ground that shapes the line

| Ground | Effect |
|---|---|
| **A bridge** (the horde crossed a river into the hex) | The front is half the smaller side's infantry wide. No more troops of either side than that fight, nor archers. Nobody maneuvers. A few infantry can hold a bridge for many rounds |
| **A mountain, river or lake** beside the hex | No pincer (a flank still works) |
| **A road** into the hex | The players' commanders know it. Every ratio is 10% lower (1.35× for a flank), and the pincer needs one rank less |
| **A fort** on the hex | Its holders get +30% attack and +30% defense. Their maneuvers need 80% of each ratio, the enemy's 125% |
| **A fort by the water** (a river or lake beside it) | Its holders can't be encircled. Flank and pincer are still possible |

## Battle reports

A round's report tells who flanked, closed a pincer or encircled whom, and
who broke through. Round 1 notes the opening volley.
