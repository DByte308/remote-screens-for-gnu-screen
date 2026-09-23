# LLM Box Terminals

A KDE Plasma 6 panel widget to view and manage GNU **screen** sessions on one or
more remote machines over SSH.

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

## Requirements

- KDE Plasma 6 (plasmoid / QML applet support)
- Konsole
- Passwordless SSH key access to the remote machines
- GNU Screen installed on the remote machines

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
