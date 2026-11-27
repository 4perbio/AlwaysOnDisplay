# AlwaysOnDisplay

**Always see your health and mana, energy or rage on the default player and target frames. You don't have to hover over the bars.**

<!-- Screenshots: upload "format 1 - cropped.png" and "format 2 - cropped.png" in the project's Images tab, then insert them here. -->

AlwaysOnDisplay writes the numbers directly on Blizzard's own unit frames and keeps them there. You don't need a new UI, there's nothing to set up, and the frames look just like before, only with the values always showing.

## Features

- **Always-visible values** on the four default bars: player health, player resource, target health and target resource. Turn each one on or off separately.
- **Every resource type:** mana, energy and rage. It switches automatically when a druid changes form, and energy and rage update with every tick.
- **Shield amount:** absorb shields show up next to your current health, like **1815 +605 / 1815**. The amount disappears when the shield breaks.
- **Four text formats:**
  - `1234 / 2000` (default)
  - `1234` (current value only)
  - `1234 / 2000 (62%)`
  - `62%`
- **Short numbers** (optional): `12.3k`, `1.5m`.
- **Minimap button** and an entry in the minimap's **AddOns** menu, both of which open the settings. You can drag the button around the minimap or hide it.
- **Lightweight:** no libraries and no extra frames. It only updates when a value actually changes.

## Settings

Open them with the minimap button, from **Options → AddOns → AlwaysOnDisplay**, or by typing **/aod**.

| Option | Default |
|---|---|
| Player health / Player resource | On |
| Target health / Target resource | On |
| Text format | `1234 / 2000` |
| Short numbers | On |
| Show shield amount | On |
| Show minimap button | On |

## Commands

- **/aod**: open the settings
- **/aod minimap**: show or hide the minimap button
- **/aod reset**: restore the default settings
- **/aod debug**: print diagnostic information to include in bug reports

## Good to know

- **Enemy health shows as a percentage** (for example `45%`). On WoW Forever's Classic-style servers, the game only gives a percentage for enemy health, not real numbers. Party members, raid members and you show full values.
- **Built for WoW Forever's protected values.** The game protects some health and power numbers (often in combat), and addons can't calculate with them. AlwaysOnDisplay only displays these values and never does math on them. If a bar can't be shown, the addon hands it back to the game's own text, so a bar is never left blank.
- **Works with the default unit frames.** If another addon replaces the player or target frame, AlwaysOnDisplay has no bars to draw on.

## Feedback and source code

Found a bug or have an idea? Open an issue on [GitHub](https://github.com/4perbio/AlwaysOnDisplay/issues). Please include the output of **/aod debug**. The source code, the full changelog and every release are on [GitHub](https://github.com/4perbio/AlwaysOnDisplay).
