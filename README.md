# Remote Screens for GNU Screen

<p align="center">
  <img src="logo.png" alt="Remote Screens logo" width="300">
  <br>
  <img src="icon.png" alt="GNU Screen icon" width="100">
</p>

Keep your remote terminal sessions within reach. Remote Screens is a KDE Plasma 6 panel widget for computers running [GNU Screen](https://www.gnu.org/software/screen/). It shows which sessions are running, lets you open them in Konsole, and gives you simple controls to start, rename, or close them.

## What you can do

- Check the panel badge for attached and detached sessions. Green means sessions are available, amber means the computer is reachable but has none, and red means it cannot be reached.
- Click the badge to see session details and open one in Konsole.
- Start a session, rename one, or close one with confirmation.
- Add multiple remote computers and switch between them from the popup.
- Choose how often to refresh and whether opening a session takes it over or shares it.

Remote Screens uses SSH to talk to GNU Screen on each computer. It does not create its own session service or keep a separate list of sessions. If a remote computer is offline, the widget cannot manage its sessions.

## Before you start

You need KDE Plasma 6 and Konsole on your desktop, plus GNU Screen and SSH access on each remote computer. Set up SSH key authentication so you can connect without an interactive password prompt. For example, make sure `ssh user@your-host screen -ls` works from your desktop before installing the widget.

## Install

From a checkout of this repository, run:

```bash
kpackagetool6 -t Plasma/Applet -i plasmoid/org.d.llmsessions
```

Then right-click your panel, choose **Add Widgets**, and add **Remote Screens for GNU Screen**. Open the widget's gear button to set up a connection. The widget includes the scripts it needs; installing them separately is optional.

To update an existing installation after pulling changes:

```bash
kpackagetool6 -t Plasma/Applet -u plasmoid/org.d.llmsessions
```

To remove it, use `kpackagetool6 -t Plasma/Applet -r org.d.llmsessions`. The widget's internal ID stays the same so existing panel placements and configuration continue to work.

## Using the widget

Select a computer in the **Box** menu, then choose a session in **Open**. The **Open** button attaches it in Konsole. **New** starts another session, **Rename** changes its name, and **Close** ends it after asking for confirmation. **Refresh** checks for changes immediately.

In the gear settings, choose an attach mode:

- **Detach and pull here** (`screen -dr`): takes over the session from another terminal.
- **Share** (`screen -x`): opens the same session without detaching it elsewhere.

Closing a session also stops programs running inside it. Check which session you selected first.

## Configuration and command-line helpers

The widget stores its settings in `~/.config/llmsessions/box.conf`. You can manage connections from the gear button; the file is shared with the optional command-line helpers. The existing config path and `llm-` helper names are retained for compatibility.

```ini
POLL_SECONDS=60
ACTIVE=LLM
CONN_LLM="192.0.2.55|user|22|dr"
CONN_PC1="192.0.2.56|user|22|x"
```

These are example addresses, not working servers. Each connection has a name, host, SSH user, port, and attach mode (`dr` or `x`). Connection names may contain letters, numbers, underscores, and hyphens, but must start with a letter or underscore. The config file is parsed as data, not executed as a shell script.

If you want to use the helpers from a terminal, install them separately:

```bash
install -d ~/.local/bin
install -m755 scripts/* ~/.local/bin/
```

| Helper | Purpose |
|---|---|
| `llm-sessions [connection]` | Show current sessions |
| `llm-open-screen [connection] <session>` | Open a session in Konsole |
| `llm-open-new [connection] [name]` | Start a session |
| `llm-rename <connection> <session> <new-name>` | Rename a session |
| `llm-close <connection> <session>` | End a session |
| `llm-config-get` | Show the current settings |
| `llm-config-apply` | Change settings from the command line |

For example, `llm-sessions PC1` lists sessions on the connection called PC1. Set `LLMBOX_CONF` to use another config file, such as when testing. The supported `llm-config-apply` operations are `set-conn NAME HOST USER PORT MODE`, `set-active NAME`, `remove-conn NAME`, and `set-poll SECONDS`; you can combine operations in one call.

## Notes

The widget is packaged in `plasmoid/org.d.llmsessions/`. The top-level `scripts/` directory contains optional CLI copies of the same scripts bundled with the widget. Development notes and Plasma-specific troubleshooting live in [`docs/PROBLEMS-FINDINGS.md`](docs/PROBLEMS-FINDINGS.md).

Licensed under GPL-2.0-or-later.
