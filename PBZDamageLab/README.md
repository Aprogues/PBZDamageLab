# PBZDamageLab — damage test lab for Phantom Blade Zero

A UE4SS Lua mod: summon a training dummy, see every hit broken down into its damage multipliers, and check which of your accessories are working right now. The panel never takes the mouse, so the camera and controls stay free while it is open.

中文说明见 [README_zh.md](README_zh.md).

Version 1.0.0

## Requirements

- Phantom Blade Zero, Steam build 26367565 (engine CL 302256). Other builds show a warning on the panel and may not work.
- A UE4SS build for Phantom Blade Zero, for example "UE4SS For Phantom Blade Zero" 1.0.3 on Nexus Mods.

## Install

1. Install UE4SS for Phantom Blade Zero first.
2. Copy the `PBZDamageLab` folder into `ue4ss/Mods/` (next to `mods.txt`).
3. Add `PBZDamageLab : 1` to `ue4ss/Mods/mods.txt`, above the `Keybinds` line.
4. If you use the "PBZ Damage Test" training dummy mod, set it to `: 0` so two dummies don't spawn.

## Keys

Edit `config.ini` to change them (restart the game after editing). Key names follow UE4SS: Insert is `INS`, Delete is `DEL` (`INSERT` and `DELETE` are accepted too). Avoid F10 and `~` (UE4SS console) and F11 (game fullscreen).

| Key | Action |
|---|---|
| F6 | Show / hide the panel |
| F7 | Summon the dummy in front of you (again = move it in front) |
| F8 | Reset statistics |
| F9 | Remove the dummy |
| F1 / F2 / F3 | Save this round as set A / B / C (compare average damage per combo) |
| F4 | Clear the comparison |
| Insert (`INS` in config.ini) | Combat mode: also count your damage to every enemy, bosses included |
| Home | Timed test: starts on your first hit, runs for `TimedSeconds` (default 30). Press again while running to stop early, while waiting to cancel |
| End | Export this round's hits to a CSV file (only when pressed), saved in the game folder under `platform\steam\ue4ss\Mods\PBZDamageLab\exports\` |

## What the panel shows

- **Stats**: hits, total damage, Sha-Chi damage, highest hit, damage per weapon, current combo (a new combo starts after 3 s without a hit) with DPS. Sha-Chi rows appear only in combat mode (the dummy has no Sha-Chi bar). Executions are not counted. Moves every weapon of a type shares (air attacks, perfect dodge …) are credited to the next weapon-specific move in the same combo, so they go to the right weapon even right after a switch.
- The dummy is the game's developer hit-only dummy: it never fights back, never deflects, has no Sha-Chi bar, and stays fixed on the spot where it was summoned.
- **Recent hits**: `damage = base × Mult × (1 + Add) × (1 + Amp)` with the values the attack started with.
- **Accessories**: every accessory you wear, colored by type (attack yellow, support blue, survival red). Attack accessories show their damage pool. The tag is green while the accessory is giving its bonus and dark gray when its condition is not met. Dance Fan, Twin Fish Pendant and Talisman of Despair also show their live value.

## Damage formula (measured on the dummy)

`damage = base × independent multipliers × (1 + additive-multiplier pool) × (1 + amplification pool)`

- **Mult (independent)**: Quick Hand Might / Pair / Pendant, Broken Vessel, weapon level bonuses. Multiply with everything.
- **Add**: Dance Fan. Bonuses inside the pool add up.
- **Amp**: Crimson Resolve, Twin Fish Pendant, Battle Wraps, Desperate Stand, Snow and Blood. Bonuses inside the pool add up.
- The two pools multiply with each other (measured: 1.6 × 1.35 = 2.16).
- An attack's damage is fixed when that attack starts. Buffs triggered in the middle of a multi-hit attack only apply from the next attack.
- Pools marked "On-hit add" and "Dmg up" are read from game data and not yet measured against the others.

## Known limits

- Accessory and weapon names come from the game's localization. The panel text itself is Chinese or English.
- Combat mode counts hits whose attack data belongs to the player. Damage from some summons or accessory procs may not be counted.
- If a combo ends with only shared moves after a weapon switch, they are credited to the weapon used before the switch.

## Bug reports

Set `Debug = true` in `config.ini`, restart, reproduce the problem, then send `ue4ss/UE4SS.log`. With `Debug = false` (default) the mod only logs start-up and errors.

## Credits

- Dummy spawning and health handling adapted from **PBZ Damage Test / PBZTrainingDummy** by xbunax (MIT, see `LICENSE-PBZTrainingDummy.txt`).
- Overlay widget pattern from **ue4ss-ModMenu** by mattdavida (MIT, see `LICENSE-ModMenu.txt`).
