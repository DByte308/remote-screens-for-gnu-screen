import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support 2.0 as Plasma5Support
import org.kde.plasma.components 3.0 as PlasmaComponents3

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation
    compactRepresentation: compact
    fullRepresentation: full

    // ----- editable config (mirrors ~/.config/llmsessions/box.conf) -----
    property var cfg: ({
        active: "LLM",
        poll: 60,
        conns: [ { name: "LLM", host: "192.0.2.55", user: "user", port: 22, mode: "dr", engine: "screen" } ]
    })
    property bool settingsOpen: false
    property bool configLoading: false
    property bool configPending: false
    property int configRevision: 0

    // parsed status state
    property int total: -1
    property int att: 0
    property int det: 0
    property bool online: false
    property string raw: ""
    property var sessions: []
    property string lastUpdate: ""
    property string engine: "screen"   // engine of the active connection
    property int herdrTabs: 0
    property int herdrWorkspaces: 0

    toolTipMainText: root.cfg.active + (root.engine === "herdr" ? " · Herdr panes" : " · GNU Screen sessions")
    toolTipSubText: (online
        ? (root.engine === "herdr"
            ? (total > 0 ? "%1 panes".arg(total) : "no panes running")
            : (total > 0 ? "%1 attached · %2 detached".arg(att).arg(det) : "no sessions running"))
        : "computer unreachable") + " · updated " + lastUpdate

    function statusColor() {
        if (!online) return "#f44336"
        return total > 0 ? "#8bc34a" : "#ffc107"
    }

    function activeConn() {
        for (var i = 0; i < cfg.conns.length; i++)
            if (cfg.conns[i].name === cfg.active) return cfg.conns[i]
        return cfg.conns.length ? cfg.conns[0] : null
    }
    function activeHost() { var c = activeConn(); return c ? c.host : "" }
    function activeUser() { var c = activeConn(); return c ? c.user : "" }
    function activeIsLocal() { var c = activeConn(); return c ? c.host === "local" : false }
    function displayHost() {
        var c = activeConn()
        if (c && c.host === "local") return "this PC"
        return c ? c.host : ""
    }

    // absolute path of a bundled script inside the installed package
    // (Plasmoid.file is not always callable; resolvedUrl is the reliable route;
    // invoked via `bash` so the exec bit is not required)
    function scriptPath(name) {
        var p = ""
        try {
            if (typeof Plasmoid.file === "function") p = Plasmoid.file("scripts", name)
        } catch (e) {}
        if (!p) p = Qt.resolvedUrl("../scripts/" + name).toString().replace(/^file:\/\//, "")
        return "bash " + p
    }

    // ---------- run status script (executable dataengine) ----------
    Plasma5Support.DataSource {
        id: execer
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            var out = data.stdout !== undefined ? String(data.stdout) : ""
            var code = data["exit code"] !== undefined ? Number(data["exit code"]) : -1
            root.parse(String(out), code === 0)
            execer.disconnectSource(sourceName)
        }

        function run() {
            execer.connectSource(root.scriptPath("llm-sessions"))
        }
    }

    // ---------- read config ----------
    Plasma5Support.DataSource {
        id: configSource
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            var out = data.stdout !== undefined ? String(data.stdout) : ""
            root.parseConfig(String(out))
            configSource.disconnectSource(sourceName)
            root.configLoading = false
            root.pollNow()
        }

        function run() {
            root.configLoading = true
            configSource.connectSource(root.scriptPath("llm-config-get"))
        }
    }

    // ---------- launch wrapper (fire-and-forget + capture stdout) ----------
    Plasma5Support.DataSource {
        id: opener
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            opener.disconnectSource(sourceName)
        }

        function run(cmd) {
            opener.connectSource(cmd)
        }
    }

    function pollNow() { if (!root.configLoading) execer.run() }
    function reloadConfig() { configSource.run() }

    // config mutations: apply then re-read + re-poll shortly after
    function runConfig(args) {
        root.configPending = true
        opener.run(root.scriptPath("llm-config-apply") + " " + args)
        applyTimer.restart()
    }
    function setActive(name) { runConfig("set-active " + name) }

    // session actions: run, then refresh the list shortly after
    function runAction(cmd) {
        opener.run(cmd)
        actionTimer.restart()
    }

    Timer { id: applyTimer; interval: 800; onTriggered: root.reloadConfig() }
    Timer { id: actionTimer; interval: 900; onTriggered: root.pollNow() }

    function openSession(index) {
        if (index < 0 || index >= root.sessions.length) return
        var id = root.sessions[index].id
        runAction(root.scriptPath("llm-open-screen") + " " + root.cfg.active + " " + id)
    }

    function openHerdr() {
        // attach the box's Herdr TUI in a new Konsole tab (fire-and-forget)
        runAction(root.scriptPath("llm-open-herdr") + " " + root.cfg.active)
    }

    // parse the KEY=VALUE output of llm-config-get into cfg
    function parseConfig(out) {
        var m, mm, re
        var poll = cfg.poll
        m = /^POLL_SECONDS=(\d+)$/m.exec(out)
        if (m) poll = Math.min(3600, Math.max(10, Number(m[1])))

        m = /^ACTIVE=(.+)$/m.exec(out)
        var activeName = m ? m[1].trim() : ""
        m = /^CONNECTIONS=(.*)$/m.exec(out)
        var order = m && m[1].trim().length ? m[1].split(",") : []

        var byName = {}
        re = /^CONN_([A-Za-z_][A-Za-z0-9_-]*)=([^|\r\n]+)\|([^|\r\n]+)\|([^|\r\n]+)\|([^|\r\n]+)(?:\|([^|\r\n]+))?$/gm
        while ((mm = re.exec(out)) !== null) {
            byName[mm[1]] = {
                name: mm[1], host: mm[2], user: mm[3],
                port: Number(mm[4]), mode: mm[5],
                engine: (mm[6] || "screen")
            }
        }

        var list = []
        for (var i = 0; i < order.length; i++)
            if (byName[order[i]]) list.push(byName[order[i]])
        for (var k in byName) {
            var found = false
            for (var j = 0; j < list.length; j++)
                if (list[j].name === byName[k].name) { found = true; break }
            if (!found) list.push(byName[k])
        }
        if (!list.length) {
            list.push({ name: "LLM", host: "192.0.2.55", user: "user", port: 22, mode: "dr", engine: "screen" })
        }
        var selected = activeName || list[0].name
        var acon = list[0]
        for (var j = 0; j < list.length; j++) {
            if (list[j].name === selected) { acon = list[j]; break }
        }
        // Assign the whole object: mutating fields of a QML var does not
        // notify bindings such as the engine-specific action row.
        root.cfg = { active: acon.name, poll: poll, conns: list }
        root.engine = acon.engine || "screen"
        root.online = false
        root.total = -1
        root.sessions = []
        root.configRevision++
        root.configPending = false
    }

    function parse(out, exitOk) {
        raw = out
        online = exitOk && out.length > 0 && out.indexOf("OFFLINE") === -1

        var list = []
        var mm

        if (root.engine === "herdr") {
            var mh = out.match(/Herdr:\s*(\d+)\s+pane?s?\s*·\s*(\d+)\s+tab?s?\s*·\s*(\d+)\s+workspace?s?/)
            if (mh) {
                total = Number(mh[1]); herdrTabs = Number(mh[2]); herdrWorkspaces = Number(mh[3])
                att = total; det = 0
            } else {
                total = -1
            }
            var reH = /^\s+([A-Za-z0-9_:-]+)\s+\[Running\]\s*(.*)$/gm
            while ((mm = reH.exec(out)) !== null) {
                list.push({
                    id: mm[1],
                    status: "Running",
                    label: "● " + mm[1] + (mm[2].length ? "  " + mm[2] : "")
                })
            }
        } else {
            var m = out.match(/Screen:\s*(\d+)\s*open\s*—\s*(\d+)\s*attached\s*·\s*(\d+)\s*detached/)
            if (m) {
                total = Number(m[1]); att = Number(m[2]); det = Number(m[3])
            } else {
                total = -1
            }
            var re = /^\s+([0-9]+\.[\w.-]+)\s+\[(Attached|Detached)\]\s*$/gm
            while ((mm = re.exec(out)) !== null) {
                list.push({
                    id: mm[1],
                    status: mm[2],
                    label: (mm[2] === "Attached" ? "● " : "○ ") + mm[1]
                })
            }
        }
        sessions = list

        lastUpdate = Qt.formatTime(new Date(), "HH:mm:ss")
    }

    Timer {
        id: pollTimer
        interval: root.cfg.poll * 1000
        running: true
        repeat: true
        onTriggered: root.pollNow()
    }

    Component.onCompleted: root.reloadConfig()

    // ---------- self-drawn terminal glyph ----------
    Component {
        id: termIcon
        Rectangle {
            property bool big: false
            radius: 2
            color: root.online ? "#202124" : "#3a1d1d"
            border.color: root.statusColor()
            border.width: 1
            implicitWidth: big ? 20 : 17
            implicitHeight: big ? 15 : 13
            Text {
                anchors.centerIn: parent
                text: ">_"
                font.family: "monospace"
                font.pixelSize: parent.big ? 10 : 8
                color: root.online ? "#e0e0e0" : "#ff8a80"
            }
        }
    }

    // ---------- panel button ----------
    Component {
        id: compact
        Item {
            Layout.minimumWidth: Kirigami.Units.iconSizes.smallMedium + label.width + Kirigami.Units.smallSpacing * 3
            Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: root.expanded = !root.expanded
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing
                Loader {
                    sourceComponent: termIcon
                    Layout.preferredWidth: 17
                    Layout.preferredHeight: 13
                }
                PlasmaComponents3.Label {
                    id: label
                    visible: root.online && root.total >= 0
                    text: root.total >= 0
                          ? (root.engine === "herdr" ? String(root.total) : root.att + "↑ " + root.det + "↓")
                          : "—"
                    Layout.alignment: Qt.AlignVCenter
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }

    // ---------- popup ----------
    Component {
        id: full
        Item {
            id: fullItem
            Layout.preferredWidth: 480
            Layout.preferredHeight: 520
            Layout.minimumWidth: 420
            Layout.minimumHeight: 420

            property string actionMode: ""   // "" | rename | new | close

            Connections {
                target: root
                function onConfigRevisionChanged() {
                    if (root.settingsOpen) fullItem.syncSettingsFields()
                }
            }

            function selSessionId() {
                var i = combo.currentIndex
                return (i >= 0 && i < root.sessions.length) ? root.sessions[i].id : ""
            }
            function selSessionName() { return selSessionId().replace(/^\d+\./, "") }

            function activeConnObj() { return root.activeConn() }

            function syncSettingsFields(connection) {
                var c = connection || activeConnObj()
                sName.text = c ? c.name : ""
                sHost.text = c ? c.host : ""
                sUser.text = c ? c.user : ""
                sPort.text = c ? String(c.port) : "22"
                sAttach.currentIndex = c && c.mode === "x" ? 1 : 0
                sLocal.checked = c && c.host === "local"
                applyLocalUi()
                sEngine.currentIndex = c && c.engine === "herdr" ? 1 : 0
                sPoll.text = String(root.cfg.poll)
            }

            function applyLocalUi() {
                sHost.enabled = !sLocal.checked
                sUser.enabled = !sLocal.checked
                sPort.enabled = !sLocal.checked
                sAttach.enabled = !sLocal.checked
                sEngine.enabled = !sLocal.checked
                if (sLocal.checked) {
                    sHost.text = "local"
                    if (sEngine.currentIndex !== 1) sEngine.currentIndex = 1
                }
            }

            function saveSettings() {
                var n = sName.text.trim(), pol = sPoll.text.trim()
                if (!/^[A-Za-z_][A-Za-z0-9_-]{0,31}$/.test(n)) { sMsg.text = "Use letters, numbers, _ or -; start with a letter or _."; return }
                if (!/^\d+$/.test(pol) || Number(pol) < 10 || Number(pol) > 3600) { sMsg.text = "Refresh interval must be 10–3600 seconds."; return }
                var cmd
                if (sLocal.checked) {
                    cmd = "set-conn " + n + " local local 0 dr --engine herdr"
                } else {
                    var h = sHost.text.trim(), u = sUser.text.trim()
                    var p = sPort.text.trim()
                    var m = sAttach.currentIndex === 1 ? "x" : "dr"
                    if (!h || !/^[A-Za-z0-9._:-]+$/.test(h)) { sMsg.text = "Enter a valid hostname or IP address."; return }
                    if (!u || !/^[A-Za-z0-9._-]+$/.test(u)) { sMsg.text = "Enter a valid SSH username."; return }
                    if (!/^\d+$/.test(p) || Number(p) < 1 || Number(p) > 65535) { sMsg.text = "Port must be 1–65535"; return }
                    var en = sEngine.currentIndex === 1 ? "herdr" : "screen"
                    cmd = "set-conn " + n + " " + h + " " + u + " " + p + " " + m + " --engine " + en
                }
                if (n !== root.cfg.active) cmd += " set-active " + n
                cmd += " set-poll " + pol
                root.runConfig(cmd)
                sMsg.text = "Saved · refreshing…"
            }
            function newConn() { sName.text = ""; sHost.text = "…"; sLocal.checked = false; sEngine.currentIndex = 0; applyLocalUi(); sMsg.text = "Enter a name and host, then select Save." }
            function delConn() {
                if (root.cfg.conns.length <= 1) { sMsg.text = "Keep at least one connection."; return }
                root.runConfig("remove-conn " + root.cfg.active)
                sMsg.text = "removed " + root.cfg.active + " · refreshing…"
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                // ---- header ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Loader {
                        sourceComponent: termIcon
                        property bool big: true
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 15
                    }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        PlasmaComponents3.Label {
                            text: root.online
                                  ? root.cfg.active + " · " + root.displayHost()
                                  : root.cfg.active + " · offline"
                            font.weight: Font.Bold
                        }
                        PlasmaComponents3.Label {
                            text: root.online
                                   ? (root.engine === "herdr"
                                        ? "%1 panes · %2 tabs".arg(root.total).arg(root.herdrTabs)
                                        : "%1 attached · %2 detached".arg(root.att).arg(root.det))
                                   : "computer unreachable"
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }
                    PlasmaComponents3.Label {
                        Layout.alignment: Qt.AlignTop
                        text: "updated " + root.lastUpdate
                        color: Kirigami.Theme.disabledTextColor
                    }
                    // gear (bundled svg — theme icons don't resolve here)
                    Item {
                        id: gear
                        width: 22; height: 22
                        Layout.alignment: Qt.AlignTop
                        property bool hovered: false
                        Rectangle {
                            anchors.fill: parent; radius: 4
                            color: Kirigami.Theme.highlightColor
                            opacity: parent.hovered ? 0.35 : 0
                        }
                        Image {
                            anchors.centerIn: parent
                            source: Qt.resolvedUrl("gear.svg")
                            sourceSize.width: 16; sourceSize.height: 16
                        }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onEntered: gear.hovered = true
                            onExited: gear.hovered = false
                            onClicked: {
                                root.settingsOpen = !root.settingsOpen
                                if (root.settingsOpen) syncSettingsFields()
                            }
                        }
                    }
                }

                // ---- connection switch ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label { text: "Box:"; color: Kirigami.Theme.textColor }
                    PlasmaComponents3.ComboBox {
                        id: connCombo
                        Layout.fillWidth: true
                        enabled: !root.configPending
                        model: root.cfg.conns
                        textRole: "name"
                        currentIndex: {
                            for (var i = 0; i < root.cfg.conns.length; i++)
                                if (root.cfg.conns[i].name === root.cfg.active) return i
                            return 0
                        }
                        onActivated: idx => {
                            if (idx >= 0 && idx < root.cfg.conns.length) {
                                var n = root.cfg.conns[idx].name
                                if (n !== root.cfg.active) {
                                    // Discard unsaved edits and show this box's own settings.
                                    if (root.settingsOpen) syncSettingsFields(root.cfg.conns[idx])
                                    root.setActive(n)
                                }
                            }
                        }
                    }
                }

                // ---- herdr quick access (engine=herdr) ----
                RowLayout {
                    visible: root.engine === "herdr"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label { text: "Herdr:"; color: Kirigami.Theme.textColor }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Kirigami.Theme.disabledTextColor
                        text: root.online
                              ? (root.total >= 0
                                  ? "%1 panes · %2 tabs · %3 workspaces".arg(root.total).arg(root.herdrTabs).arg(root.herdrWorkspaces)
                                  : "no panes")
                              : "server unreachable"
                    }
                    PlasmaComponents3.Button {
                        text: "Open Herdr…"
                        enabled: root.online
                        onClicked: root.openHerdr()
                    }
                }

                // ---- settings panel (gear) ----
                ColumnLayout {
                    visible: root.settingsOpen
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Label { text: "Connection:"; Layout.alignment: Qt.AlignVCenter }
                        PlasmaComponents3.TextField {
                            id: sName; Layout.fillWidth: true
                            placeholderText: "PC1"
                        }
                        PlasmaComponents3.Button { text: "New…"; onClicked: newConn() }
                        PlasmaComponents3.Button { text: "Delete"; onClicked: delConn() }
                    }

                    GridLayout {
                        columns: 4
                        rowSpacing: Kirigami.Units.smallSpacing
                        columnSpacing: Kirigami.Units.smallSpacing
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Host:"; Layout.alignment: Qt.AlignRight }
                        PlasmaComponents3.TextField { id: sHost; Layout.fillWidth: true; placeholderText: "192.0.2.55" }
                        PlasmaComponents3.Label { text: "Port:" }
                        PlasmaComponents3.TextField { id: sPort; Layout.preferredWidth: 70; placeholderText: "22" }
                        PlasmaComponents3.Label { text: "User:"; Layout.alignment: Qt.AlignRight }
                        PlasmaComponents3.TextField { id: sUser; Layout.fillWidth: true; placeholderText: "user" }
                        PlasmaComponents3.Label { text: "Refresh (s):" }
                        PlasmaComponents3.TextField { id: sPoll; Layout.preferredWidth: 70; placeholderText: "60" }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Attach mode:" }
                        PlasmaComponents3.ComboBox {
                            id: sAttach
                            Layout.fillWidth: true
                            model: [
                                { value: "dr", text: "Detach from box & pull here (screen -dr)" },
                                { value: "x",  text: "Share session, stay on box (screen -x)" }
                            ]
                            textRole: "text"; valueRole: "value"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Engine:" }
                        PlasmaComponents3.ComboBox {
                            id: sEngine
                            Layout.fillWidth: true
                            model: [
                                { value: "screen", text: "GNU Screen — classic sessions" },
                                { value: "herdr",  text: "Herdr — panes & tabs (socket API)" }
                            ]
                            textRole: "text"; valueRole: "value"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        PlasmaComponents3.CheckBox {
                            id: sLocal
                            text: "This PC (local Herdr) — no SSH"
                            onToggled: {
                                applyLocalUi()
                                if (!checked) {
                                    var c = activeConnObj()
                                    sEngine.currentIndex = c && c.engine === "herdr" ? 1 : 0
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Button { text: "Save"; onClicked: saveSettings() }
                        PlasmaComponents3.Button { text: "Cancel"; onClicked: root.settingsOpen = false }
                        PlasmaComponents3.Label {
                            id: sMsg; Layout.fillWidth: true; elide: Text.ElideRight
                            color: Kirigami.Theme.positiveTextColor
                        }
                    }
                }

                // ---- session picker + actions (screen only) ----
                RowLayout {
                    visible: root.engine !== "herdr"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label { text: "Open:"; color: Kirigami.Theme.textColor }
                    PlasmaComponents3.ComboBox {
                        id: combo
                        Layout.fillWidth: true
                        Layout.minimumWidth: 180
                        model: root.sessions
                        textRole: "label"
                        enabled: root.online && root.sessions.length > 0
                        displayText: root.online && root.sessions.length > 0
                                     ? currentText
                                     : (root.online ? "no sessions running" : "computer offline")
                    }
                    PlasmaComponents3.Button {
                        text: "Open"
                        enabled: root.online && root.sessions.length > 0 && combo.currentIndex >= 0
                        onClicked: root.openSession(combo.currentIndex)
                    }
                    PlasmaComponents3.Button {
                        text: "Rename"
                        enabled: combo.currentIndex >= 0
                        onClicked: { actionMode = "rename"; rmName.text = selSessionName() }
                    }
                    PlasmaComponents3.Button {
                        text: "New"
                        onClicked: { actionMode = "new"; nwName.text = "" }
                    }
                    PlasmaComponents3.Button {
                        text: "Close…"
                        enabled: combo.currentIndex >= 0
                        onClicked: {
                            if (selSessionId()) {
                                clMsg.text = "End session \"" + selSessionId() + "\" on " + root.cfg.active + "? This closes everything running in it."
                                actionMode = "close"
                            }
                        }
                    }
                }

                // ---- action input bar ----
                RowLayout {
                    visible: actionMode !== "" && root.engine !== "herdr"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    // rename
                    RowLayout {
                        visible: actionMode === "rename"
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Label { text: "New name:" }
                        PlasmaComponents3.TextField {
                            id: rmName; Layout.fillWidth: true
                            placeholderText: "session name"
                        }
                        PlasmaComponents3.Button {
                            text: "Apply"
                            onClicked: {
                                var nn = rmName.text.trim()
                                if (!/^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$/.test(nn)) {
                                    actMsg.text = "Use letters, numbers, dots, _ or - for the name."
                                    return
                                }
                                var id = selSessionId()
                                if (id && nn) {
                                    root.runAction(root.scriptPath("llm-rename") + " " + root.cfg.active + " " + id + " " + nn)
                                    actMsg.text = "Renamed to " + nn
                                }
                                actionMode = ""
                            }
                        }
                        PlasmaComponents3.Button { text: "✕"; onClicked: actionMode = "" }
                    }

                    // new terminal
                    RowLayout {
                        visible: actionMode === "new"
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Label { text: "Name (optional):" }
                        PlasmaComponents3.TextField {
                            id: nwName; Layout.fillWidth: true
                            placeholderText: "e.g. build"
                        }
                        PlasmaComponents3.Button {
                            text: "Start"
                            onClicked: {
                                var nn = nwName.text.trim()
                                if (nn && !/^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$/.test(nn)) {
                                    actMsg.text = "Use letters, numbers, dots, _ or - for the name."
                                    return
                                }
                                root.runAction(root.scriptPath("llm-open-new") + " " + root.cfg.active + " " + nn)
                                actMsg.text = "Starting session…"
                                actionMode = ""
                            }
                        }
                        PlasmaComponents3.Button { text: "✕"; onClicked: actionMode = "" }
                    }

                    // close confirm
                    RowLayout {
                        visible: actionMode === "close"
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Label {
                            id: clMsg; Layout.fillWidth: true; elide: Text.ElideRight
                            color: Kirigami.Theme.negativeTextColor
                        }
                        PlasmaComponents3.Button {
                            text: "End it"
                            onClicked: {
                                var id = selSessionId()
                                if (id) {
                                    root.runAction(root.scriptPath("llm-close") + " " + root.cfg.active + " " + id)
                                    actMsg.text = "Closing " + id + "…"
                                }
                                actionMode = ""
                            }
                        }
                        PlasmaComponents3.Button { text: "Cancel"; onClicked: actionMode = "" }
                    }

                    PlasmaComponents3.Label {
                        id: actMsg
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Kirigami.Theme.positiveTextColor
                    }
                }

                // ---- status text ----
                PlasmaComponents3.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    PlasmaComponents3.TextArea {
                        text: root.raw
                        readOnly: true
                        selectByMouse: true
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: TextEdit.Wrap
                    }
                }

                // ---- footer ----
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Button { text: "Refresh"; onClicked: root.pollNow() }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents3.Label {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.online
                              ? (root.activeIsLocal()
                                    ? root.cfg.active + " · local Herdr (this PC)"
                                    : root.cfg.active + " · " + root.activeUser() + "@" + root.activeHost())
                              : ""
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
            }
        }
    }
}
