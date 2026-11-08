import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// VPN status on the bar: an upright pineapple while the tunnel's network
// interface exists, upside down and muted while it does not. Click for a
// drawer with Connect or Disconnect.
//
// A preset (AirVPN/Eddie, WireGuard, Mullvad) supplies the interface and
// commands; any of them can be overridden in the widget settings, and the
// Custom preset uses only the overrides.
BarWidget {
  id: root
  moduleName: "taylorburke.vpn-pineapple"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function setting(key, fallback) {
    var v = root.settings ? root.settings[key] : undefined
    return v === undefined || v === null ? fallback : v
  }
  function trimmed(key) { return String(setting(key, "")).trim() }

  readonly property string preset: {
    var p = String(setting("preset", "AirVPN (Eddie)"))
    return ["AirVPN (Eddie)", "WireGuard (wg-quick)", "Mullvad", "Custom"].indexOf(p) >= 0 ? p : "AirVPN (Eddie)"
  }
  readonly property bool isEddie: preset === "AirVPN (Eddie)"
  readonly property string presetIface:
    isEddie ? "Eddie"
    : preset === "WireGuard (wg-quick)" ? "wg0"
    : preset === "Mullvad" ? "wg0-mullvad"
    : ""
  // Linux interface names: at most 15 characters, no slash or whitespace.
  // Anything else is ignored so it never reaches the status check.
  readonly property string iface: {
    var v = trimmed("interface") || presetIface
    return /^[A-Za-z0-9_.:@-]{1,15}$/.test(v) ? v : ""
  }
  readonly property string connectOverride: trimmed("connectCommand")
  readonly property string disconnectOverride: trimmed("disconnectCommand")
  readonly property string vpnName: trimmed("name") || (preset === "Custom" ? "VPN" : preset.replace(/ \(.*\)$/, ""))
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
      'if [ -n "$i" ] && [ -e "/sys/class/net/$i" ]; then s=up; else s=down; fi; ' +
      'if [ -n "$p" ] && pgrep -f "$p" >/dev/null; then r=run; else r=stop; fi; ' +
      'a=$(ip -4 -o addr show dev "$i" 2>/dev/null | awk "{print \\$4}" | cut -d/ -f1); ' +
      'echo "$s $r ${a:--}"',
      "sh", root.iface, root.isEddie ? root.eddiePattern : ""]
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

  // Runs cmd with bash in a new terminal (for sudo prompts). Extra args
  // reach cmd as "$1", "$2"... so values are never spliced into the script.
  // A failing command keeps the window open so the error can be read.
  function terminalCommand(cmd, args) {
    return ["omarchy-launch-terminal", "bash", "-c",
      'bash -c "$1" vpn-pineapple "${@:2}"; rc=$?; ' +
      'if (( rc != 0 )); then echo; echo "Exited ($rc). Press Enter to close."; read -r; fi',
      "vpn-pineapple", cmd].concat(args || [])
  }

  readonly property bool canConnect:
    connectOverride !== "" || (preset !== "Custom" && iface !== "")
  readonly property bool canDisconnect:
    disconnectOverride !== "" || (preset !== "Custom" && iface !== "")
  // Eddie can be running with no tunnel yet; offer Disconnect then too.
  readonly property bool active: connected || (isEddie && eddieRunning)

  function connectVpn() {
    if (active || pending !== "" || !canConnect) return
    startPending("connecting")
    // Close the drawer first: while open, its HyprlandFocusGrab keeps focus
    // on the popup, so a sudo terminal would open unfocused.
    root.popupOpen = false
    if (connectOverride !== "") {
      Quickshell.execDetached(setting("useTerminal", true)
        ? terminalCommand(connectOverride) : ["sh", "-c", connectOverride])
    } else if (isEddie) {
      Quickshell.execDetached(["omarchy-launch-terminal", "bash", pluginDir + "/vpn-connect.sh"])
    } else if (preset === "WireGuard (wg-quick)") {
      Quickshell.execDetached(terminalCommand('sudo wg-quick up "$1"', [iface]))
    } else if (preset === "Mullvad") {
      Quickshell.execDetached(["mullvad", "connect"])
    }
  }

  function disconnectVpn() {
    if (!active || pending !== "" || !canDisconnect) return
    startPending("disconnecting")
    if (disconnectOverride !== "") {
      root.popupOpen = false
      Quickshell.execDetached(setting("useTerminal", true)
        ? terminalCommand(disconnectOverride) : ["sh", "-c", disconnectOverride])
    } else if (isEddie) {
      // SIGINT = Ctrl+C in Eddie's console: its clean ExitStart() path,
      // which saves the remembered login, same as pressing x.
      Quickshell.execDetached(["pkill", "-INT", "-f", eddiePattern])
    } else if (preset === "WireGuard (wg-quick)") {
      root.popupOpen = false
      Quickshell.execDetached(terminalCommand('sudo wg-quick down "$1"', [iface]))
    } else if (preset === "Mullvad") {
      Quickshell.execDetached(["mullvad", "disconnect"])
    }
  }

  readonly property string statusText:
    iface === "" ? strings.t("status.noInterface", "No interface set")
    : pending === "connecting" ? strings.t("status.connecting", "Connecting…")
    : pending === "disconnecting" ? strings.t("status.disconnecting", "Disconnecting…")
    : connected ? strings.t("status.connected", "Connected")
    : isEddie && eddieRunning ? strings.t("status.eddieNoTunnel", "Eddie running, tunnel down")
    : strings.t("status.disconnected", "Disconnected")

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
    onEntered: if (root.bar) root.bar.showTooltip(root, strings.t("tooltip", "%1: %2").arg(root.vpnName).arg(root.statusText))
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
            text: root.vpnName
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
        readonly property bool wantsDisconnect: root.active
        text: root.pending === "connecting" ? strings.t("status.connecting", "Connecting…")
              : root.pending === "disconnecting" ? strings.t("status.disconnecting", "Disconnecting…")
              : wantsDisconnect ? strings.t("button.disconnect", "Disconnect") : strings.t("button.connect", "Connect")
        iconText: wantsDisconnect ? "󰅖" : "󰌘"
        foreground: root.bar.foreground
        bordered: true
        horizontalPadding: Style.spacing.panelGap
        verticalPadding: Style.spacing.controlPaddingY
        enabled: root.pending === "" && (wantsDisconnect ? root.canDisconnect : root.canConnect)
        opacity: enabled ? 1.0 : 0.5
        onClicked: wantsDisconnect ? root.disconnectVpn() : root.connectVpn()
      }
    }
  }
}
