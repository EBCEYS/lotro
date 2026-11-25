# InstanceLockTimer

A [The Lord of the Rings Online](https://www.lotro.com) plugin that tracks your
instance lock cooldowns: start a one-hour timer with a single click and keep an
eye on how many you have used today.

![Main window with three active one-hour timers](./imgs/InstanceLockTimer1.png)

*The main window with three active one-hour timers running.*

![The same timers after renaming](./imgs/InstanceLockTimer2.png)

*The same three timers after renaming them — click a timer's name to edit it.*

![Timer start offer](./imgs/InstanceLockTimer3.png)

*The plugin will offer you to start timer on mission acception.*

## Features

- **One-click 1h timer** — the big button starts a standard one-hour instance
  lock timer.
- **Active counter** — shows how many timers are running and decreases
  automatically whenever a timer expires.
- **Per-day usage counter** — "Today: N / 100" counts how many timers you
  started during the current server day, drawn in a gradient colour from green
  (0) to red (100) with a matching progress bar.
- **Server day reset** — the daily counter resets at the server day change
  (by default 07:00 UTC in summer, 08:00 UTC in winter; configurable). Active
  timers are *not* reset; they keep counting down until they expire.
- **Rename timers** — click a timer's name to rename it: press Enter (or click
  anywhere else) to confirm, Escape to cancel.
- **Cancel early** — the "X" on a row removes that timer; if you started it
  during the current server day, the daily counter gets that start back
  (it never goes below 0).
- **Mission offers** — the moment you accept a mission, the game writes
  "New Quest: Mission: *\<name\>*" to chat and the plugin opens a small
  offer window: one click starts a 1h timer named after that mission.
  The warp announcement ("New Quest: *\<name\>*" without the "Mission:"
  prefix) is deliberately ignored, so the offer appears only on
  accepting. English client text only.
- **Survives logout** — timers are stored per character with absolute expiry
  times, so they keep running through logout, relogging and
  `/plugins unload` + `/plugins load`. If
  the server day changed while you were offline, the daily counter resets on
  load.
- **Screen icon** — a small gold-framed "ILT" icon gives quick access to the
  main window (see below).

## Icon

The plugin puts a small "ILT" icon on the screen. The first time, it is
placed next to the main window: to the left of it, or to the right, above or
below it if there is no room on that side. After that it stays where you
drag it.

- **Left click** — shows the main window when it is hidden. When the main
  window is shown, a click hides it, and also closes an open mission offer
  window (the offer is dismissed; no timer is started).
- **Left drag** — moves the icon (unless it is locked). Dragging a locked
  icon does nothing — it doesn't count as a click.
- **Right click** — opens a menu:
  1. **Lock icon / Unlock icon** — locks the icon in place so it can't be
     dragged by accident (also in the settings). The text shows what the
     item will do.
  2. **Show main window / Hide main window** — only the main window.
  3. **Options...** — opens the plugin settings.
- **HUD toggle (F12)** — hides the icon, the main window and an open mission
  offer together with the game's HUD, and brings them back on the next
  press. While the HUD is hidden, `/ilt show` / `/ilt hide` still work and
  are remembered.

The icon position and whether the main window is shown are remembered per
character, so a hidden window stays hidden after relogging or
`/plugins unload` + `/plugins load`.

## Installation

1. Copy the `InstanceLockTimer` folder (containing `Main.lua` and
   `InstanceLockTimer.plugin`) into the game's plugin directory:

   ```
   Documents\The Lord of the Rings Online\Plugins\
   ```

   so that the files end up as:

   ```
   Documents\The Lord of the Rings Online\Plugins\InstanceLockTimer\Main.lua
   Documents\The Lord of the Rings Online\Plugins\InstanceLockTimer\InstanceLockTimer.plugin
   ```

   Nothing needs to be created, changed or edited.

2. In game, load the plugin:

   ```
   /plugins load InstanceLockTimer
   ```

   (You can also enable it once in the plugin manager and save it in your
   character's UI settings.)

## Commands

| Command | Description |
| --- | --- |
| `/ilt show` | Show the main window |
| `/ilt hide` | Hide the main window |
| `/ilt toggle` | Show the main window if it is hidden, hide it if it is shown |
| `/ilt options` | Open the plugin settings in the plugin manager |
| `/ilt add <minutes>` | Start a custom-length timer (e.g. `/ilt add 1` for a quick test) |
| `/ilt resetdaily` | Reset the daily counter |
| `/ilt help` | Command overview |

`/InstanceLockTimer` works as a full alias for `/ilt`.

## How it works

- Timer state is saved per character via the game's PluginData storage:
  each timer stores its absolute expiry time (server time), so nothing has to
  keep running while you are logged out.
- The daily counter belongs to the *server day*, which changes at the
  configured reset time (07:00 UTC in summer, 08:00 UTC in winter by default).
- Timer names, the window position, whether the window is shown and the icon
  position are saved alongside the timers.

## Settings

Open the plugin manager, select **InstanceLockTimer** and press **Options**
(or type `/ilt options`). Changes apply immediately and are saved
account-wide.

| Setting | Default | Meaning |
| --- | --- | --- |
| Reset time (UTC, summer) | `07:00` | Server day change in summer time (hour and minutes, 5-minute steps) |
| Winter time | on | In winter the daily reset happens one hour later |
| Detect winter time automatically | on | Switch winter/summer time on the US daylight saving dates (2nd Sunday of March / 1st Sunday of November) |
| Offer mission timers | on | Watch chat for accepted missions and offer a named timer |
| Width | `300` | Main window width, 240–600 px |
| Visible timer rows | `8` | Timer rows shown before a "+N more" line appears (1–20); the height follows the number of timers |
| Lock icon position | off | The screen icon can't be dragged (same as **Lock icon** in the icon menu) |

The panel also shows when the next daily reset happens. Changing the reset
settings does not reset today's counter.

## Tuning

A few remaining constants are in the `CONFIGURATION` section at the top of
`Main.lua`:

| Constant | Default | Meaning |
| --- | --- | --- |
| `TIMER_DURATION` | `3600` | Length of a standard timer, seconds |
| `DAILY_MAX` | `100` | Daily gradient: green at 0, red at `DAILY_MAX` |

## Author & license

**Ebceys** — version 1.4.0.

Released under the [Beer-ware License](../LICENSE).