import QtQuick
import qs.Commons
import qs.Ui
import qs.Ui as Ui

// Settings shown inside the drawer when the gear is pressed. Every change is
// saved to shell.json at once through the shell's updateEntryInline, so the
// widget's `settings` (and this view) update in place.
Column {
  id: view
  required property var widget
  readonly property var settings: widget.settings || ({})
  readonly property color ink: widget.bar ? widget.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(ink, 1.4)
  property string error: ""
  signal done()

  spacing: Style.space(8)

  function apply(patch) {
    error = widget.saveSettings(patch) ? "" : widget.strings.t("settings.saveFailed", "Could not save this change. Try again.")
  }
  function patch(key, value) { var o = {}; o[key] = value; return o }

  component PlainLabel: Text {
    textFormat: Text.PlainText
    color: view.ink
    font.family: view.widget.bar ? view.widget.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  component SettingRow: Item {
    property string label: ""
    property string help: ""
    default property alias control: slot.children
    width: parent.width
    implicitHeight: Math.max(labels.implicitHeight, slot.implicitHeight) + Style.space(8)
    Column {
      id: labels
      anchors.left: parent.left; anchors.right: slot.left; anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      PlainLabel { width: parent.width; text: label; wrapMode: Text.WordWrap }
      PlainLabel { visible: help !== ""; width: parent.width; text: help; color: view.dim; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
    }
    Item { id: slot; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
  }

  component SettingField: Ui.TextField {
    property string key: ""
    width: Style.space(190)
    foreground: view.ink
    // Seeded, never bound: binding `text` to the settings would loop. Re-seed
    // when settings change elsewhere, unless the field is being edited.
    function seed() { if (!activeFocus) text = String(view.settings[key] === undefined ? "" : view.settings[key]) }
    Component.onCompleted: seed()
    Connections { target: view; function onSettingsChanged() { seed() } }
    onEditingFinished: if (text.trim() !== String(view.settings[key] || "")) view.apply(view.patch(key, text.trim()))
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(title.implicitHeight, back.implicitHeight)
    PlainLabel {
      id: title
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: view.widget.strings.t("settings.title", "VPN Pineapple settings")
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }
    PanelActionButton {
      id: back
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅖"
      tooltipText: view.widget.strings.t("settings.back", "Back")
      foreground: view.ink
      onClicked: view.done()
    }
  }

  PanelSeparator { foreground: view.ink }

  SettingRow {
    label: view.widget.strings.t("settings.preset", "VPN")
    help: view.widget.strings.t("settings.presetHelp", "Supplies the interface and commands")
    Dropdown {
      width: Style.space(190)
      showLabel: false
      foreground: view.ink
      options: view.widget.presets.map(function (p) { return { value: p, label: p } })
      value: view.widget.preset
      onChanged: function (v) { view.apply({ preset: v }) }
    }
  }
  SettingRow {
    label: view.widget.strings.t("settings.name", "Name")
    help: view.widget.strings.t("settings.blankPreset", "Blank uses the preset's")
    SettingField { key: "name" }
  }
  SettingRow {
    label: view.widget.strings.t("settings.interface", "Network interface")
    help: view.widget.presetIface !== ""
      ? view.widget.strings.t("settings.interfaceHelp", "Blank uses %1").arg(view.widget.presetIface)
      : view.widget.strings.t("settings.interfaceHelpCustom", "As shown by ip link")
    SettingField { key: "interface" }
  }
  SettingRow {
    label: view.widget.strings.t("settings.connect", "Connect command")
    help: view.widget.strings.t("settings.commandHelp", "Blank uses the preset's. Runs with bash")
    SettingField { key: "connectCommand" }
  }
  SettingRow {
    label: view.widget.strings.t("settings.disconnect", "Disconnect command")
    help: view.widget.strings.t("settings.commandHelp", "Blank uses the preset's. Runs with bash")
    SettingField { key: "disconnectCommand" }
  }
  SettingRow {
    label: view.widget.strings.t("settings.terminal", "Run commands in a terminal")
    help: view.widget.strings.t("settings.terminalHelp", "For sudo prompts. Applies to the two commands above")
    ToggleSwitch {
      checked: view.widget.setting("useTerminal", true) === true
      foreground: view.ink
      onToggled: view.apply({ useTerminal: !checked })
    }
  }

  PlainLabel {
    visible: view.error !== ""
    width: parent.width
    text: view.error
    color: view.widget.bar ? view.widget.bar.urgent : Color.urgent
    wrapMode: Text.WordWrap
  }
}
