# Recent Apps

A bar history button that drops a panel listing your last ten apps, for the
Omarchy shell.

A history icon sits in the bar. Clicking it opens a panel listing the last ten
apps you opened or focused, newest first, each with its icon, name and window
titles. Clicking a row launches or focuses that app.

## Requirements

- Omarchy shell
- Hyprland (the tracker subscribes to the compositor's event socket)
- `python3`
- `uwsm-app` for launching apps, so they come up in your session

## Install

```sh
omarchy plugin add https://github.com/RobbieUK1/omarchy-recent-apps.git --enable
omarchy restart shell
```

The tracker ships in `bin/` but has to live outside the plugin directory:

```sh
mkdir -p ~/.config/omarchy/bar/scripts
install -m 755 bin/recent-apps ~/.config/omarchy/bar/scripts/recent-apps
```

It needs to be running to record anything:

```sh
~/.config/omarchy/bar/scripts/recent-apps &
```

Then right-click your bar -> **Configure bar** (or edit
`~/.config/omarchy/shell.json`) and add the widget:

```json
"right": [
  { "id": "robbie.recent-apps" }
]
```

## Interaction

| Input      | Action                          |
|------------|---------------------------------|
| Left click | toggle the panel, refreshing it |

The panel also refreshes when the bar tells it to, and the tracker's `--once`
mode captures the current focus and running clients so the list is populated
immediately rather than only after you switch windows.

## Terminals are collapsed on purpose

A terminal window is recorded as the terminal app itself — one entry per
terminal emulator — no matter which program is running inside it. A terminal
showing `btop`, `python3` or an editor still gets a single entry, never one per
foreground program. Each app appears once: re-opening or re-focusing it just
moves it to the front rather than adding a duplicate.

## The tracker

`recent-apps` subscribes to the Hyprland event socket and records newly opened
and focused windows into `~/.config/omarchy/bar/recent-apps.json`, most recent
first, capped at 10 entries.

```sh
recent-apps           # daemon mode, tracks events
recent-apps --once    # capture current focus + clients, then exit
recent-apps --clear   # empty the list
```

The panel's **Clear** button in the header runs `--clear`.

An advisory lock keeps two trackers from writing the file at once. `--once`
intentionally skips the lock, because it only reads.

## What is not in this repo

`recent-apps.json` is your own app history and is gitignored. It is created on
your machine as the tracker runs.

## License

MIT
