import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "fuzzy.js" as Fuzzy

Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "Hack Nerd Font"

  // Driven from the bar; the menu only reads it and asks to be closed.
  property bool open: false
  signal closeRequested
  signal wallpaperPickerRequested

  // Menu tree. An entry has either `submenu` (a key of `pages`) or `action`.
  PowerActions { id: power }

  // Power entries mirror the bar's power menu one-to-one.
  readonly property var powerItems: power.actions.map(a => ({
    key: a.key, label: a.label, icon: a.icon, hint: a.hint,
    danger: a.danger, instant: !!a.instant, action: "power", cmd: a.cmd
  }))

  readonly property var pages: ({
    root: { title: "Menu", items: [
      { label: "Style", icon: String.fromCodePoint(0xF03D8), hint: "Appearance", submenu: "style" },
      { label: "Power", icon: String.fromCodePoint(0xF0425), hint: "Lock, log out, suspend, restart, shut down", submenu: "power" }
    ]},
    style: { title: "Style", items: [
      { label: "Wallpaper picker", icon: String.fromCodePoint(0xF0E09), hint: "Pick a wallpaper", action: "wallpaper" }
    ]},
    power: { title: "Power", items: root.powerItems }
  })

  // Two-step like the bar's power menu: first activation arms, second runs.
  property string pending: ""

  property string page: "root"
  property string query: ""
  property int selected: 0

  readonly property var results: Fuzzy.filter(pages[page].items, query, e => e.label)

  function reset(): void {
    pending = "";
    page = "root";
    query = "";
    selected = 0;
  }

  function goBack(): void {
    pending = "";
    if (page === "root") { closeRequested(); return; }
    page = "root";
    query = "";
    selected = 0;
  }

  function activate(entry): void {
    if (!entry) return;
    if (entry.submenu) {
      page = entry.submenu;
      query = "";
      selected = 0;
    } else if (entry.action === "wallpaper") {
      wallpaperPickerRequested();
    } else if (entry.action === "power") {
      if (entry.instant || pending === entry.key) {
        pending = "";
        closeRequested();
        powerProc.command = entry.cmd;
        powerProc.running = true;
      } else {
        pending = entry.key;
      }
    }
  }

  Process {
    id: powerProc
    running: false
  }

  onOpenChanged: if (open) { reset(); Qt.callLater(() => searchInput.forceActiveFocus()); }
  onSelectedChanged: pending = ""
  onResultsChanged: selected = Math.min(selected, Math.max(0, results.length - 1))

  PanelWindow {
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-startmenu"

    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }

    // Click outside to dismiss. Transparent so the desktop stays readable.
    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }

    Rectangle {
      id: box
      anchors.centerIn: parent
      width: 300
      height: layout.implicitHeight + 24
      radius: 12
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1

      Accessible.role: Accessible.Dialog
      Accessible.name: "Start menu"

      MouseArea { anchors.fill: parent }

      ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Header doubles as the way back out of a submenu.
        Row {
          spacing: 6
          Text {
            visible: root.page !== "root"
            text: String.fromCodePoint(0xF004D)
            color: root.theme.textMuted
            font.pixelSize: 13
            font.family: root.font
            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goBack()
            }
          }
          Text {
            text: root.pages[root.page].title
            color: root.theme.accentPrimary
            font.pixelSize: 13
            font.family: root.font
            font.bold: true
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 34
          radius: 8
          color: root.theme.bgSurface
          border.color: searchInput.activeFocus ? root.theme.accentPrimary : root.theme.bgBorder
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Text {
              text: String.fromCodePoint(0xF0349)
              color: root.theme.textMuted
              font.pixelSize: 13
              font.family: root.font
            }

            TextInput {
              id: searchInput
              Layout.fillWidth: true
              color: root.theme.textPrimary
              font.pixelSize: 13
              font.family: root.font
              clip: true
              text: root.query
              onTextChanged: root.query = text
              Accessible.role: Accessible.EditableText
              Accessible.name: "Search menu"

              Keys.onEscapePressed: root.goBack()
              Keys.onDownPressed: root.selected = Math.min(root.selected + 1, root.results.length - 1)
              Keys.onUpPressed: root.selected = Math.max(root.selected - 1, 0)
              Keys.onReturnPressed: root.activate(root.results[root.selected])
              Keys.onEnterPressed: root.activate(root.results[root.selected])
              Keys.onPressed: event => {
                if (event.key === Qt.Key_Backspace && text === "" && root.page !== "root") {
                  root.goBack();
                  event.accepted = true;
                }
              }

              Text {
                anchors.fill: parent
                text: "Search..."
                color: root.theme.textMuted
                font: parent.font
                visible: parent.text === ""
              }
            }
          }
        }

        Repeater {
          model: root.results

          Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: index === root.selected
            readonly property bool armed: root.pending === modelData.key

            Layout.fillWidth: true
            height: 36
            radius: 8
            color: armed ? (modelData.danger ? root.theme.accentRed : root.theme.accentPrimary)
                 : current ? root.theme.bgSelected : "transparent"

            Accessible.role: Accessible.Button
            Accessible.name: modelData.label

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 10

              Text {
                text: row.modelData.icon
                color: row.armed ? root.theme.bgBase
                     : row.modelData.danger ? root.theme.accentRed : root.theme.accentPrimary
                font.pixelSize: 15
                font.family: root.font
              }
              Text {
                Layout.fillWidth: true
                text: row.armed ? "Press again to confirm" : row.modelData.label
                color: row.armed ? root.theme.bgBase : root.theme.textPrimary
                font.pixelSize: 13
                font.family: root.font
              }
              Text {
                visible: !!row.modelData.submenu
                text: String.fromCodePoint(0xF0142)
                color: root.theme.textMuted
                font.pixelSize: 14
                font.family: root.font
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selected = row.index
              onClicked: root.activate(row.modelData)
            }
          }
        }

        Text {
          visible: root.results.length === 0
          Layout.alignment: Qt.AlignHCenter
          text: "No matches"
          color: root.theme.textMuted
          font.pixelSize: 12
          font.family: root.font
        }
      }
    }
  }
}
