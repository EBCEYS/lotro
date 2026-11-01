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
  (07:00 UTC). Active timers are *not* reset; they keep counting down until
  they expire.
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
  times, so they keep running through logout, `/ui reload` and relogging. If
  the server day changed while you were offline, the daily counter resets on
  load.

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
| `/ilt add <minutes>` | Start a custom-length timer (e.g. `/ilt add 1` for a quick test) |
| `/ilt resetdaily` | Reset the daily counter |
| `/ilt help` | Command overview |

`/InstanceLockTimer` works as a full alias for `/ilt`.

## How it works

- Timer state is saved per character via the game's PluginData storage:
  each timer stores its absolute expiry time (server time), so nothing has to
  keep running while you are logged out.
- The daily counter belongs to the *server day*, which changes at 07:00 UTC.
- Timer names and the window position are saved alongside the timers.

## Tuning

The tweakable values are in the `CONFIGURATION` section at the top of
`Main.lua`:

| Constant | Default | Meaning |
| --- | --- | --- |
| `TIMER_DURATION` | `3600` | Length of a standard timer, seconds |
| `DAY_RESET_UTC_HOUR` | `7` | UTC hour at which the daily counter resets |
| `DAILY_MAX` | `100` | Daily gradient: green at 0, red at `DAILY_MAX` |
| `MAX_VISIBLE_ROWS` | `8` | Timer rows shown before a "+N more" line appears |
| `OFFER_MISSION_TIMERS` | `true` | Watch chat for accepted missions and offer a named timer |

## Author & license

**Ebceys** — version 1.1.

Released under the MIT License.