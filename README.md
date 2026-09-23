# LLM Box Terminals

<p align="center"><img src="icon.png" alt="LLM Box Terminals" width="225"></p>

A KDE Plasma 6 panel widget that keeps an eye on the open terminals of one or
more remote machines and lets you manage them from your desktop: see which
GNU Screen sessions are running and whether they are attached, open one in a
Konsole tab, rename it, start a new one, or close it.

## Features

- Panel badge with a live summary (screens open, attached/detached counts).
  Color: green = online with sessions, amber = online but none, red = unreachable
  (read-only status polling over SSH).
- Popup with full status text and an **Open** dropdown that attaches a session
  in a Konsole tab.
- Session actions: **Rename**, **New terminal**, **Close** (with confirmation).
- **Multiple connections** (LLM, PC1, ...) with a box switcher; the badge
  follows the active connection.
- **Gear settings** panel: add/edit/delete connections, attach mode, refresh
  interval.
- Auto-refresh (configurable); all panel copies of the widget share one SSH
  poll per connection.

## Built on GNU Screen

This tool is a front-end to the **GNU Screen** terminal multiplexer running on
each remote box. It has no session tracking of its own: every piece of
information it shows and every action it performs goes through `screen` on the
remote side.

- List sessions: `screen -ls`
- Open a session: `screen -dr` (pull here) or `screen -x` (share)
- New terminal: `screen -S <name>`
- Rename: `screen -X sessionname <newname>`
- Close: `screen -X quit`

So **GNU Screen must be installed on every machine this connects to**; it is
the base the tool runs on. Without it there is nothing to list, open, rename,
or close (the badge just shows no sessions / offline).

## Requirements

- KDE Plasma 6 (plasmoid / QML applet support)
- Konsole
- Passwordless SSH key access to the remote machines
- **GNU Screen on the remote machines** (required base, see above)

## Install

```bash
# the widget is self-contained (scripts are bundled in the package)
kpackagetool6 -t Plasma/Applet -i plasmoid/org.d.llmsessions

# OPTIONAL — only if you also want the helpers on the command line:
install -m755 scripts/* ~/.local/bin/
```

Upgrade in place with `-u`, remove with `-r`:
`kpackagetool6 -t Plasma/Applet -u plasmoid/org.d.llmsessions`

Then right-click a panel → *Add Widgets* → "LLM Box Terminals".

## Usage

| In the popup | Does |
|---|---|
| `Box` | switch the active connection |
| `Open` | attach the selected session in a Konsole tab |
| `Rename` | rename the selected session (`screen -X sessionname`) |
| `New` | start a new screen terminal on the box (optional name) |
| `Close…` | end a session after confirmation (`screen -X quit`) |
| `Refresh` | poll immediately |
| ⚙ gear | connection settings (see below) |

## Configuration

Stored in `~/.config/llmsessions/box.conf` (shared by the widget and scripts):

```ini
POLL_SECONDS=60
ACTIVE=LLM
CONN_LLM="192.0.2.55|user|22|dr"
CONN_PC1="192.0.2.56|user|22|x"
```

- Connection entry: `name = host|user|port|mode`.
- `mode dr` = detach from the box and pull the session here (`screen -dr`).
- `mode x`  = shared multi-attach; the session stays on the box (`screen -x`).
- Connection names: `[A-Za-z_][A-Za-z0-9_-]*` (no spaces).
- The file is parsed, never shell-sourced (values contain `|`).

## Scripts (command line)

Same path the widget uses, handy for scripts/cron:

| Script | Purpose |
|---|---|
| `llm-config-get` | print effective config (KEY=VALUE) |
| `llm-config-apply` | validate & save config. Subcommands: `set-conn NAME HOST USER PORT MODE`, `set-active NAME`, `remove-conn NAME`, `set-poll SECONDS`. Atomic write, nothing saved if invalid. |
| `llm-sessions [conn]` | read-only status poll |
| `llm-open-screen [conn] <session>` | attach a session in Konsole |
| `llm-open-new [conn] [name]` | start a new terminal on the box |
| `llm-rename <conn> <session> <newname>` | rename a session |
| `llm-close <conn> <session>` | end a session |

Example:

```bash
llm-config-apply set-conn PC1 192.0.2.56 user 22 x set-active PC1
llm-sessions PC1
llm-open-new PC1 build
```

All scripts read `$LLMBOX_CONF` to use a custom config file (for testing).

## Project layout

```
├── README.md
├── docs/PROBLEMS-FINDINGS.md      # development notes & gotchas
├── plasmoid/org.d.llmsessions/    # the Plasma widget (self-contained)
│   └── contents/
│       ├── ui/                    #   main.qml + gear.svg
│       └── scripts/               #   bundled helper scripts
└── scripts/                       # same scripts, for CLI use (optional)
```

## License

GPL-2.0-or-later (see `plasmoid/org.d.llmsessions/metadata.json`).
