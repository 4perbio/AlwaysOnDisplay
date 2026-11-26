# AlwaysOnDisplay

A World of Warcraft **Forever** addon that always shows the numbers for your health and resource (mana, energy, rage) on the default player and target frames. You don't have to hover over a bar to see them.

```
 ┌──────────────────────────────┐
 │  1234 / 2000 (62%)           │  ← health
 │  500 / 1000 (50%)            │  ← mana / energy / rage
 └──────────────────────────────┘
```

## Features

- Always-visible text on four bars: **player health**, **player resource**, **target health** and **target resource**. Each one can be turned on or off separately.
- Works for every resource type, and switches automatically when a druid changes form.
- Energy and rage update with every tick.
- Three text formats: `1234 / 2000 (62%)`, `1234 / 2000`, or `62%`.
- Optional short numbers: `12.3k`, `1.5m`.
- Enemy targets show `45%`. Forever's Classic-style servers only give a percentage for enemy health, not real numbers. Party and raid members, and you, show full values.
- Dead and ghost units show `Dead` or `Ghost`. The resource text is hidden for targets with no resource.
- While the addon's text is on for a bar, it hides the game's own hover text on that bar so the two never overlap.

## Installation

1. Download the latest `AlwaysOnDisplay-vX.Y.Z.zip` from the [Releases page](https://github.com/4perbio/AlwaysOnDisplay/releases/latest), then unzip it so that the `AlwaysOnDisplay` folder lands in
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
   (or copy the `AlwaysOnDisplay` folder from this repository there).
2. Restart the game, or type `/reload`, and make sure **AlwaysOnDisplay** is enabled in the AddOns list on the character screen.

<details><summary>Manual install from source</summary>

1. Copy the `AlwaysOnDisplay` folder (the one containing `AlwaysOnDisplay.toc`) into
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
2. Restart the game, or type `/reload`, and make sure **AlwaysOnDisplay** is enabled in the AddOns list on the character screen.

</details>

For development, link the folder instead of copying it, so a `/reload` picks up your changes:

```powershell
New-Item -ItemType Junction `
  -Path   "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\AlwaysOnDisplay" `
  -Target "C:\Users\absolute\projects\AlwaysOnDisplay\AlwaysOnDisplay"
```

## Usage

Everything is on by default. To change it:

- Open **Options → AddOns → AlwaysOnDisplay**, or
- type `/aod` to open that panel directly.

| Option          | Default             | What it does                                              |
|-----------------|---------------------|-----------------------------------------------------------|
| Player health   | on                  | Health text on your own frame                             |
| Player resource | on                  | Mana / energy / rage text on your own frame               |
| Target health   | on                  | Health text on the target frame                           |
| Target resource | on                  | Mana / energy / rage text on the target frame             |
| Text format     | `1234 / 2000 (62%)` | Value and percent, value only, or percent only            |
| Short numbers   | on                  | Shortens numbers from 10,000 up (`12.3k`, `1.5m`)         |

Changes apply immediately and are saved account-wide in `WTF\Account\<account>\SavedVariables\AlwaysOnDisplay.lua`.

### Slash commands

| Command      | Effect                          |
|--------------|---------------------------------|
| `/aod`       | Open the options panel          |
| `/aod reset` | Restore all options to defaults |

## Troubleshooting

**"AlwaysOnDisplay: could not find some unit frame bars" in chat.**
The addon looks for the default bars under several known names:
`PlayerFrameHealthBar` / `PlayerFrameManaBar` / `TargetFrameHealthBar` / `TargetFrameManaBar`, the modern nested `PlayerFrame.PlayerFrameContent…` paths, and `PlayerFrame.healthbar` / `.manabar`. If a game update renames them, or another unit frame addon replaces them, they won't be found. Hover the bar, type `/fstack` to see its frame name, and add it to `BAR_CANDIDATES` in `AlwaysOnDisplay/Core.lua`.

**Text shows twice.**
Another addon, or the game's *Status Text* interface option, is drawing text on the bar too. Turn off one of them.

**Target health shows only a percent.**
This is expected for enemies. The server only tells the game the percentage.

## How it works

The addon draws **its own text** on top of each Blizzard bar rather than switching the game's hover text on. That makes it independent of the game's *Status Text* setting, and it never calls protected Blizzard code, so it can't cause taint or "action blocked" errors in combat.

```
AlwaysOnDisplay/
├── AlwaysOnDisplay.toc   addon info (Interface 16001, SavedVariables)
├── Core.lua              finding the bars, formatting, event handling
└── Options.lua           settings panel and /aod
```

- **`Core.lua`**
  - `BAR_CANDIDATES` holds the list of places to look for each bar.
  - `Setup` creates an overlay frame 5 levels above each bar, holding one centered `TextStatusBarText` font string.
  - `UpdateDisplay` reads `UnitHealth` and `UnitPower(unit, UnitPowerType(unit))`, then formats the result.
  - The events listened to are `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `PLAYER_TARGET_CHANGED`, plus `UNIT_HEALTH`, `UNIT_MAXHEALTH`, `UNIT_POWER_UPDATE`, `UNIT_POWER_FREQUENT`, `UNIT_MAXPOWER`, `UNIT_DISPLAYPOWER` and `UNIT_FLAGS`. The unit events only fire for `player` and `target`.
- **`Options.lua`**: builds the panel with the modern `Settings` API (`RegisterVerticalLayoutCategory`, `RegisterAddOnSetting`, `CreateCheckbox`, `CreateDropdown`). Each setting is bound directly to `AlwaysOnDisplayDB`, and every change calls `ns.Refresh()`.

## Development & tests

The tests run outside the game, against a mocked WoW API (`tests/wow_mock.lua`). They are executed by [fengari](https://github.com/fengari-lua/fengari), a Lua VM in JavaScript, so you only need **Node.js**. No Lua install is required.

```powershell
npm install   # once
npm test
```

The tests cover:

- **Saved variables**: defaults are filled in and existing values are kept.
- **Finding the bars**: all three frame layouts work, a missing bar gives a single warning, and the overlay is created once.
- **Formatting**: every format and short-number case, and rounding.
- **Target**: no target, enemy percent versus party values, no resource, dead/ghost.
- **Live updates**: energy ticks, shapeshifts, and filtering events by unit.
- **Options**: settings registration and types, the dropdown choices, live changes from the panel, and `/aod` / `/aod reset`.

To add a test, write a `test("name", function() ... end)` block in `tests/test_core.lua` or `tests/test_options.lua`. `mock.new{layout=…, savedDB=…}` builds a fresh client, `mock.login(env)` loads the addon, `mock.fire(env, event, ...)` sends events, and `mock.visibleText(env, "playerHealth")` reads what's on a bar. A new test file must also be added to `SUITES` in `tests/run.lua`.

## Releases

Every push to `main` triggers `.github/workflows/release.yml`. It runs the tests, and if they pass it publishes a GitHub release `vX.Y.Z` with an installable zip. The zip's `.toc` has `## Version:` set to that number. Pull requests run the tests only.

| In any pushed commit message | Version change      |
|------------------------------|---------------------|
| *(nothing)*                  | `1.2.3` → `1.2.4`   |
| `#minor`                     | `1.2.3` → `1.3.0`   |
| `#major`                     | `1.2.3` → `2.0.0`   |

### CurseForge

After the GitHub release, the same zip is uploaded to CurseForge and tagged with the WoW Forever game version (`1.60.1`). The release notes are used as the changelog. The upload is skipped until both of these are set in the GitHub repo under **Settings → Secrets and variables → Actions**:

| Name              | Kind     | Value                                                                    |
|-------------------|----------|--------------------------------------------------------------------------|
| `CF_API_KEY`      | Secret   | CurseForge API token (Account settings → API tokens)                     |
| `CF_PROJECT_ID`   | Variable | The numeric Project ID from the "About Project" box, not the URL name    |
| `CF_GAME_VERSION` | Variable | *Optional.* Game version name, if Forever moves past `1.60.1`            |

From a terminal:

```powershell
gh secret set CF_API_KEY -R 4perbio/AlwaysOnDisplay          # prompts for the token
gh variable set CF_PROJECT_ID -R 4perbio/AlwaysOnDisplay --body 123456
```

The upload logic is in `.github/scripts/curseforge-upload.sh`.

The first release uses the version already written in `AlwaysOnDisplay.toc` (`1.0.0`). After that, the git tags are the source of truth. The `## Version:` line in the repository is not updated, so only the release zip carries the real number.

Fengari runs Lua 5.3, but the game runs Lua 5.1. Keep the addon code to features both versions have: no `//`, no `goto`, no integer-only operations.

The mock only imitates the API. It can't prove the real frame names on Forever, so after any change also check in game: `/reload`, target a few units, and toggle the options.
