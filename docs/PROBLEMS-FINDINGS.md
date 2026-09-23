# Development notes & problems found (not part of the shipped program)

Everything nontrivial learned while building this widget on Plasma 6.7.4 /
Wayland / Nobara. Kept out of the repo README on purpose; recorded so we don't
rediscover it. Mostly relevant while changing `main.qml`/the scripts.

## 1. The popup wouldn't open: two root causes

**Symptom:** left-click did nothing; no popup, zero QML errors.

### 1a. Custom compact reps need their own MouseArea (the click bug)
Per the [KDE widget docs](https://develop.kde.org/docs/plasma/widget/setup/):
> *"If you change the compact representation, you will need to use a
> `MouseArea` to toggle the `plasmoid.expanded` property."*

The shell does not auto-open the popup for a custom `compactRepresentation`.
Fix:
```qml
MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: root.expanded = !root.expanded
}
```

### 1b. Popup size comes from Layout.preferred*, not implicit size
Forcing `root.expanded = true` and logging showed the full rep instantiated at
`0x-1` (invisible). The popup is sized from the full rep's
`Layout.preferredWidth/Height`. Set those (and minimums) on the full-rep root
Item.

## 2. Theme icons do NOT resolve in this plasmoid

`icon.name:` on buttons renders a "missing icon" glyph (the gear showed broken);
`image://icon/` is not registered either. Fixes used:
- Gear: bundled `gear.svg` loaded with `Image { source: Qt.resolvedUrl("gear.svg") }`.
- Buttons: text-only (no `icon.name`).

## 3. Plasma 6 QML API moves

- Root must be `PlasmoidItem` (`import org.kde.plasma.plasmoid`), not
  `Item` + `Plasmoid.*` attaches.
- `PlasmaCore.IconItem` is gone from `org.kde.plasma.core` in 6.7.
- `PlasmaCore.DataSource` is gone; the legacy engine lives at
  `import org.kde.plasma.plasma5support` → `Plasma5Support.DataSource`
  (that's what enables `engine: "executable"`).
- `PlasmaCore.Units` / `PlasmaCore.Theme` resolve as `undefined` in applet QML
  here → use `Kirigami.Units` / `Kirigami.Theme`.
- `X-Plasma-API-Minimum-Version: "6.0"` is mandatory in `metadata.json` or
  Plasma 6 rejects the widget.

## 4. Diagnostic / tooling gotchas

- `kpackagetool6 -u` is upgrade, not uninstall (uninstall is `-r`).
- `plasmashell evaluateScript` executes but discards return values and does not
  allow a top-level `return`; you cannot read state back from it.
- Plasma drops synthetic input (`ydotool` clicks never reach widgets), so a
  widget can only be click-tested with a real user mouse.
- `onNewData: (sourceName, data) => { ... }` avoids the "Injection of
  parameters into signal handlers is deprecated" warning.
- Cross-component gotcha: ids of children are not reachable as `root.<id>`
  from inside separately-scoped `compact`/`full` Components. Expose a plain
  method on the root and call `root.method()`.

## 5. Sourcing a config with `|` in values silently breaks bash

First attempt stored entries as `CONN_PC1=192.0.2.56|user|22|dr` and the config
scripts **sourced** the file. Result: reads came back empty and
`remove-conn` said "no such connection".

Cause: on `source`, `CONN_PC1=192.0.2.56|user|22|dr` is parsed as the assignment
`CONN_PC1=192.0.2.56` **piped** into the commands `user`, `22`, `dr` (which fail,
silently under `2>/dev/null`). A variable assignment does not quote the `|`
after `=`.

Fix used: scripts **parse** the file textually into associative arrays and
never source it; values are written quoted (`CONN_LLM="...|...|...|..."`)
so even accidental sourcing is safe. `llm-sessions`/`llm-open-screen` resolve
the connection through `llm-config-get` output (single source of truth).

## 6. Notes on pi vision (unrelated, but blocked visual QA during dev)

- `vision.json` had pointed at a model id missing from the model registry; the
  image-capable model is set via `/vision model <id>` with the model id **only**
  (no `provider/` prefix, or you get a double-prefixed lookup failure).

## Known quirks not worth fixing

- Remote `.bashrc` prints `/home/USER/.local/bin: Is a directory` on every
  login (broken PATH line, harmless).
- Status text shows German-comma decimals (`0,07`) and `4days` from the remote
  locale; cosmetic.
- Fallback if the panel popup ever breaks: left-click → executable engine →
  `kdialog --menu` picker → Konsole attach (no panel-popup dependency).
