import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Recent apps bar widget: a history icon in the bar that drops a panel listing
// the last ten apps opened or focused (tracked by bar/scripts/recent-apps).
// Each row shows the app icon on the left and the app name on the right;
// clicking a row launches that app.
//
//   Left click  toggle recents panel

Panel {
  id: root
  moduleName: "robbie.recent-apps"
  ipcTarget: "robbie.recent-apps"

  property var recents: []
  property var rows: []
  property var metaById: ({})
  property bool clearBusy: false

  readonly property int maxRows: 10
  readonly property int rowHeight: Style.space(38)
  readonly property int panelPadding: Style.spacing.popupPadding
  readonly property string iconGlyph: "\uf1da"

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property string scriptPath: String(setting("exec", "~/.config/omarchy/bar/scripts/recent-apps"))
  readonly property string dataPath: String(setting("file", "~/.config/omarchy/bar/recent-apps.json"))

  function expandPath(s) {
    if (String(s).charAt(0) === "~") return (Quickshell.env("HOME") || "/root") + String(s).substring(1)
    return String(s)
  }

  // ---- data loading ----

  FileView {
    id: cacheFile
    path: Quickshell.env("HOME") + "/.config/omarchy/bar/recent-apps.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.onRecentsLoaded(text())
  }

  function onRecentsLoaded(text) {
    var data = {}
    try { data = JSON.parse(text) } catch (e) { return }
    var list = Array.isArray(data.recents) ? data.recents : []
    var out = []
    for (var i = 0; i < list.length && i < root.maxRows; i++) {
      var r = list[i]
      var cls = String(r.class || "")
      if (!cls) continue
      out.push({
        class: cls,
        name: String(r.name || cls),
        tui: String(r.tui || ""),
        cmd: String(r.cmd || "")
      })
    }
    root.recents = out
    root.buildRows()
  }

  // ---- app metadata (icon + launch id) from AppLibrary ----

  function refreshMeta() {
    var lib = root.bar && root.bar.shell && root.bar.shell.appLibrary
    var map = {}
    if (lib && typeof lib.sortedEntries === "function") {
      var entries = lib.sortedEntries("")
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i] && entries[i].entry
        var id = String((entry && entry.id) || "").toLowerCase()
        if (id.length > 0) map[id] = entry
      }
    }
    root.metaById = map
    root.buildRows()
  }

  function metaForClass(cls) {
    var m = root.metaById
    var c = String(cls || "").toLowerCase().replace(/\.desktop$/, "")
    if (m[c]) return m[c]
    if (m[c + ".desktop"]) return m[c + ".desktop"]
    var best = null
    for (var id in m) {
      if (id.indexOf(c) !== -1 || c.indexOf(id) !== -1) {
        if (!best || id.length < String(best.id).length) best = m[id]
      }
    }
    return best
  }

  function resolveIcon(cls) {
    var key = String(cls || "")
    var entry = null
    try { entry = DesktopEntries.heuristicLookup(key) } catch (e) { entry = null }
    var iconName = entry && entry.icon ? String(entry.icon) : key.toLowerCase()
    return iconName !== "" ? Quickshell.iconPath(iconName, true) : ""
  }

  function iconForTui(tuiKey, cls) {
    var iconName = ""
    var entry = null
    try { entry = DesktopEntries.heuristicLookup(String(tuiKey || "")) } catch (e) { entry = null }
    if (entry && entry.icon) {
      iconName = String(entry.icon)
    } else {
      try { entry = DesktopEntries.heuristicLookup(String(cls || "")) } catch (e) { entry = null }
      if (entry && entry.icon) iconName = String(entry.icon)
    }
    return iconName !== "" ? Quickshell.iconPath(iconName, true) : ""
  }

  function buildRows() {
    var lib = root.bar && root.bar.shell && root.bar.shell.appLibrary
    var out = []
    for (var i = 0; i < root.recents.length && i < root.maxRows; i++) {
      var r = root.recents[i]
      var cls = String(r.class || "")
      if (!cls) continue
      var isTui = String(r.tui || "") !== ""
      var entry = null
      if (isTui) {
        try { entry = DesktopEntries.heuristicLookup(r.tui) } catch (e) { entry = null }
      } else {
        entry = root.metaForClass(cls)
      }
      var name = entry ? String(entry.name || entry.id || r.name || (isTui ? r.tui : cls)) : (r.name || cls)
      var icon = isTui ? root.iconForTui(r.tui, cls) : root.resolveIcon(cls)
      out.push({
        class: cls,
        name: name,
        icon: icon,
        desktopId: entry ? String(entry.id || "") : "",
        tui: r.tui,
        cmd: r.cmd
      })
    }
    root.rows = out
  }

  // ---- launcher ----

  Process {
    id: execProc
  }

  function terminalBin(cls) {
    var m = {
      "alacritty": "alacritty",
      "kitty": "kitty",
      "foot": "foot",
      "ghostty": "ghostty",
      "com.mitchellh.ghostty": "ghostty",
      "wezterm": "wezterm",
      "konsole": "konsole",
      "org.kde.konsole": "konsole",
      "gnome-terminal": "gnome-terminal",
      "org.gnome.Terminal": "gnome-terminal",
      "xfce4-terminal": "xfce4-terminal",
      "xterm": "xterm"
    }
    return m[String(cls || "").toLowerCase()] || ""
  }

  function launchTui(row) {
    var lib = root.bar && root.bar.shell && root.bar.shell.appLibrary
    if (row.desktopId && lib && typeof lib.launch === "function") {
      lib.launch(row.desktopId, row.name)
      return
    }
    var cmd = String(row.cmd || "")
    var term = root.terminalBin(row.class)
    if (term && cmd) {
      var escaped = cmd.replace(/'/g, "'\\''")
      execProc.command = ["bash", "-lc",
        "uwsm-app -- " + term + " -e bash -lc '" + escaped + "'"]
      if (!execProc.running) execProc.running = true
      return
    }
    execProc.command = ["uwsm-app", "--", row.class]
    if (!execProc.running) execProc.running = true
  }

  function launchRow(row) {
    var lib = root.bar && root.bar.shell && root.bar.shell.appLibrary
    if (row.tui) {
      root.launchTui(row)
    } else if (row.desktopId && lib && typeof lib.launch === "function") {
      lib.launch(row.desktopId, row.name)
    } else {
      execProc.command = ["uwsm-app", "--", row.class]
      if (!execProc.running) execProc.running = true
    }
    root.close()
  }

  // ---- ensure daemon + refresh ----

  Process {
    id: ensureProc
    running: true
    command: ["bash", "-c",
      "setsid " + root.expandPath(root.scriptPath) + " >/dev/null 2>&1 &"]
  }

  Process {
    id: onceProc
    command: ["bash", "-lc", root.expandPath(root.scriptPath) + " --once"]
    onExited: cacheFile.reload()
  }

  Process {
    id: clearProc
    command: ["bash", "-lc", root.expandPath(root.scriptPath) + " --clear"]
    onExited: {
      root.clearBusy = false
      cacheFile.reload()
    }
  }

  function clearAll() {
    if (root.rows.length === 0) return
    root.clearBusy = true
    root.rows = []
    if (!clearProc.running) clearProc.running = true
  }

  function refresh() {
    cacheFile.reload()
    if (!onceProc.running) onceProc.running = true
  }

  // ---- retry meta until AppLibrary is available ----

  Timer {
    id: metaRetry
    interval: 300
    running: true
    repeat: true
    onTriggered: {
      var lib = root.bar && root.bar.shell && root.bar.shell.appLibrary
      if (!(lib && typeof lib.sortedEntries === "function")) return
      var entries = lib.sortedEntries("")
      if (!(entries && entries.length > 0)) return
      root.refreshMeta()
      metaRetry.stop()
    }
  }

  // ---- lifecycle ----

  function togglePanel() {
    root.toggle()
    if (root.opened) {
      root.refreshMeta()
      root.refresh()
    }
  }

  function triggerPress(button) {
    root.togglePanel()
  }

  Component.onCompleted: {
    syncClickRegistration()
    root.refreshMeta()
    root.refresh()
  }
  Component.onDestruction: if (root.bar && root.bar.unregisterClickTarget) root.bar.unregisterClickTarget(root)

  function syncClickRegistration() {
    if (root.bar && root.bar.registerClickTarget) root.bar.registerClickTarget(root)
  }

  // ---- bar label ----

  implicitWidth: Math.max(12, label.implicitWidth + Style.spaceReal(horizontalMargin) * 2)
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal
  property real horizontalMargin: 7.5

  Text {
    id: label
    anchors.centerIn: parent
    text: root.iconGlyph
    color: bar ? bar.barForeground : Color.foreground
    font.family: bar ? bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.title
    renderType: Text.NativeRendering
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root, "Recent apps — left: menu")
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: root.togglePanel()
  }

  // ---- dropdown panel ----
  //
  // PopupCard owns the popup surface, the edge-aware anchoring, outside-click
  // dismissal and the popout coordination. PopupCard rather than KeyboardPanel
  // because this panel has no text input and must not take keyboard focus from
  // whatever the user was typing in when they clicked the bar.

  PopupCard {
    id: panel
    anchorItem: label
    owner: root
    bar: root.bar
    open: root.opened
    padding: root.panelPadding
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.cappedContentHeight(panelColumn.implicitHeight)

    Column {
      id: panelColumn
      width: parent.width
      spacing: Style.spacing.sm

      Item {
        id: header
        width: parent.width
        implicitHeight: hero.implicitHeight

        PanelHero {
          id: hero
          width: parent.width
          title: "Recent Apps"
          meta: root.rows.length + (root.rows.length === 1 ? " app" : " apps")
          foreground: Color.popups.text
          fontFamily: bar ? bar.fontFamily : Style.font.family
          readonly property bool canClear: root.rows.length > 0 && !root.clearBusy
          readonly property bool clearing: root.clearBusy
          function clearClick() { root.clearAll() }
          iconComponent: Component {
            Text {
              text: root.iconGlyph
              color: Color.popups.text
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.display
            }
          }

          trailingControl: Component {
            Button {
              visible: hero && hero.canClear
              text: hero && hero.clearing ? "" : "Clear All"
              iconText: hero && hero.clearing ? "\uf021" : ""
              iconSpinning: hero && hero.clearing
              fontSize: Style.font.caption
              foreground: hero ? hero.foreground : Color.foreground
              bordered: true
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(3)
              tooltipText: "Remove all recent apps"
              onClicked: if (hero) hero.clearClick()
            }
          }
        }
      }

      PanelSeparator { foreground: Color.popups.text }

      Repeater {
        model: root.rows

        delegate: Component {
          Item {
            width: panelColumn.width - root.panelPadding * 2
            implicitHeight: root.rowHeight
            height: implicitHeight

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.launchRow(modelData)

              Rectangle {
                anchors.fill: parent
                radius: Style.space(6)
                color: rowMouse.containsMouse ? Util.alpha(Color.popups.text, 0.08) : "transparent"
              }
            }

            Item {
              id: iconBox
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(34)
              height: Style.space(34)

              Image {
                id: appIcon
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: modelData.icon || ""
                asynchronous: true
                visible: source !== ""
              }

              Text {
                anchors.centerIn: parent
                visible: !appIcon.visible
                text: (modelData.class.charAt(0) || "?").toUpperCase()
                color: Color.accent
                font.family: bar ? bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            Text {
              anchors.left: iconBox.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: modelData.name
              color: Color.popups.text
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }
      }

      Text {
        visible: root.rows.length === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "No recent apps"
        color: Util.alpha(Color.popups.text, 0.5)
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
