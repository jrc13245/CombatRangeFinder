# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CombatRangeFinder is a World of Warcraft 1.12 (Vanilla/Turtle WoW) addon that provides visual melee combat indicators: a directional arrow between player and target (color-coded by range/facing/behind status), and raid markers rendered at enemy feet in 3D world space.

## External Dependencies

- **SuperWoW.dll** — provides `SetAutoloot` global and extended API
- **VanillaUtils.dll** — provides `UnitXP()` function for positional data (`unitPosition`, `unitFacing`, `cameraPosition`, `cameraPitch`, `cameraFoV`, `distanceBetween`, `behind`, `inSight`)
- **Nampower** (optional) — provides `GetSpellIdForName` and `IsSpellInRange` for more accurate melee range checking
- **Optional addon deps**: SuperAPI, pfUI (declared in .toc)

The addon will show an error popup and bail out early if SuperWoW or VanillaUtils are missing.

## Architecture

This is a single-file addon (`CombatRangeFinder.lua`) with no build system, tests, or linter. The `.toc` file declares metadata and loads the single Lua file.

### Key systems in CombatRangeFinder.lua:

- **DotPool** (line ~115): Object pool pattern for reusable UI frames ("dots") that get projected into 3D world space. Each dot has a world position (x,y,z) and gets screen-projected every frame.
- **3D-to-screen projection** (lines ~610-787): Camera position/orientation is read via `UnitXP` APIs, then each dot's world coordinates are transformed through yaw/pitch rotation and perspective projection to screen coordinates. FOV is calibrated via a piecewise-linear lookup table (`ScaleFOV`).
- **Arrow indicator** (lines ~789-875): A textured line drawn between player and target screen positions. Color encodes state: green=in-range+facing, orange=not-facing, teal=behind-target, red=out-of-range, gray=no-line-of-sight. Uses `RotateTexture` for angle alignment.
- **Raid markers** (lines ~446-531): 8 markers from the raid icon texture atlas, projected at marked unit feet positions. Distance-based scaling fades them out beyond 40 yards.
- **Melee range detection** (`FindMeleeSpell`, `IsInRange`): Checks if player has a known melee ability, then uses either Nampower's `IsSpellInRange` or action bar `IsActionInRange` to determine true melee range. Falls back to distance-based check (5 yards, 6.5 for Tauren).

### Saved variables

Per-character settings stored in `CRFDB.settings` (SavedVariablesPerCharacter). Toggled via `/crf <option>`. Settings defined in the `commands` table (~line 336).

## WoW 1.12 Lua Environment

- Lua 5.1 runtime — use `getn()`, `table.getn()`, `string.gfind()` (not `string.gmatch`), `math.mod()` (not `%` operator for modulo)
- No `local function` closures in OnEvent handlers — uses `this`, `event`, `arg1`..`arg9` implicit upvalues
- Frame API: `CreateFrame`, `SetScript("OnUpdate")`, `SetScript("OnEvent")`, `SetPoint`, `SetTexCoord`, etc.
- All WoW API globals (`UnitExists`, `UnitName`, `GetTime`, etc.) are undefined from a static analysis perspective — these are provided by the game client at runtime. LSP "undefined-global" warnings for WoW API functions are expected and not bugs.
- `math.mod` is deprecated in Lua 5.3+ but correct for this 1.12 client environment.

## Slash Commands

`/crf` — shows all options. `/crf <option>` toggles boolean settings or sets numeric ones.
