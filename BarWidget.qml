import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// AirVPN (Eddie) status on the bar: an upright pineapple while the tunnel
// is up, upside down while it is down. Click for a drawer with Connect or
// Disconnect.
BarWidget {
  id: root
  moduleName: "taylorburke.vpn-pineapple"

  readonly property string iface: "Eddie"
  // Matches only the real Eddie engine, not its root-owned elevated helper
  // (eddie-cli-elevated), so pkill -INT reaches the process that saves the
  // profile. Never print this process's command line: it can hold the login.
  readonly property string eddiePattern: "^/usr/lib/eddie-cli/eddie-cli( |$)"
  readonly property string pluginDir:
    decodeURIComponent(Qt.resolvedUrl(".").toString())
      .replace(/^file:\/\//, "").replace(/\/$/, "")

  property bool connected: false
  property bool eddieRunning: false
  property string address: ""
  // "" | "connecting" | "disconnecting": set by a button, cleared when the
  // state it is waiting for arrives or the timeout fires.
  property string pending: ""
  property real pendingSince: 0
  property bool sawEddie: false
  property bool popupOpen: false

  function startPending(kind) {
    pending = kind
    pendingSince = Date.now()
    sawEddie = false
    pendingTimeout.restart()
  }

  function close() { popupOpen = false }

  implicitWidth: glyph.implicitWidth + Style.space(10)
  implicitHeight: barSize

  // One line per check: "<up|down> <run|stop> <ipv4 or ->"
  Process {
    id: check
    command: ["sh", "-c",
      'i="$1"; p="$2"; ' +
      'if [ -e "/sys/class/net/$i" ]; then s=up; else s=down; fi; ' +
      'if pgrep -f "$p" >/dev/null; then r=run; else r=stop; fi; ' +
      'a=$(ip -4 -o addr show dev "$i" 2>/dev/null | awk "{print \\$4}" | cut -d/ -f1); ' +
      'echo "$s $r ${a:--}"',
      "sh", root.iface, root.eddiePattern]
    stdout: SplitParser {
      onRead: function (line) {
        var f = line.trim().split(" ")
        if (f.length < 3) return
        root.connected = f[0] === "up"
        root.eddieRunning = f[1] === "run"
        root.address = f[2] === "-" ? "" : f[2]
        if (root.pending === "connecting") {
          if (root.connected) {
            root.pending = ""
          } else if (root.eddieRunning) {
            root.sawEddie = true
          } else if (root.sawEddie || Date.now() - root.pendingSince > 20000) {
            // Eddie started and quit without a tunnel (e.g. no saved login),
            // or never started at all: the attempt failed, unlock the button.
            root.pending = ""
          }
        }
        if (root.pending === "disconnecting" && !root.eddieRunning && !root.connected) root.pending = ""
      }
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!check.running) check.running = true
  }

  // Last-resort unlock if neither outcome is ever observed.
  Timer {
    id: pendingTimeout
    interval: 45000
    onTriggered: root.pending = ""
  }

  function connectVpn() {
    if (eddieRunning || pending !== "") return
    startPending("connecting")
    // Close the drawer first: while open, its HyprlandFocusGrab keeps focus
    // on the popup, so the sudo terminal would open unfocused.
    root.popupOpen = false
    Quickshell.execDetached(["omarchy-launch-terminal", "bash", pluginDir + "/vpn-connect.sh"])
  }

  // SIGINT = Ctrl+C in Eddie's console: its clean ExitStart() path, which
  // saves the remembered login, same as pressing x.
  function disconnectVpn() {
    if (!eddieRunning || pending !== "") return
    startPending("disconnecting")
    Quickshell.execDetached(["pkill", "-INT", "-f", eddiePattern])
  }

  readonly property string statusText:
    pending === "connecting" ? "Connecting…"
    : pending === "disconnecting" ? "Disconnecting…"
    : connected ? "Connected"
    : eddieRunning ? "Eddie running, tunnel down"
    : "Disconnected"

  Text {
    id: glyph
    anchors.centerIn: parent
    textFormat: Text.PlainText
    // Nerd Font md-fruit_pineapple: normal bar color while connected, muted
    // (darkened, same as Kopia's idle state) while down.
    text: String.fromCodePoint(0xF1046)
    color: root.connected ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.4)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
    rotation: root.connected ? 0 : 180
    Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on color {
      enabled: !root.bar || root.bar.foregroundAnimationEnabled
      ColorAnimation { duration: 160 }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.popupOpen = !root.popupOpen
    onEntered: if (root.bar) root.bar.showTooltip(root, "AirVPN: " + root.statusText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(240))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String.fromCodePoint(0xF1046)
          rotation: root.connected ? 0 : 180
          color: root.connected ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.displayLarge
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: "AirVPN"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            text: root.statusText + (root.connected && root.address ? " · " + root.address : "")
            color: root.bar.foreground
            opacity: 0.7
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Button {
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property bool wantsDisconnect: root.eddieRunning || root.connected
        text: root.pending === "connecting" ? "Connecting…"
              : root.pending === "disconnecting" ? "Disconnecting…"
              : wantsDisconnect ? "Disconnect" : "Connect"
        iconText: wantsDisconnect ? "󰅖" : "󰌘"
        foreground: root.bar.foreground
        bordered: true
        horizontalPadding: Style.spacing.panelGap
        verticalPadding: Style.spacing.controlPaddingY
        enabled: root.pending === ""
        opacity: enabled ? 1.0 : 0.5
        onClicked: wantsDisconnect ? root.disconnectVpn() : root.connectVpn()
      }
    }
  }
}
