import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import "../start-menu"

Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "Hack Nerd Font"

  // Driven from the bar; the popup only reads it and asks to be closed.
  property bool open: false
  signal closeRequested

  function close(): void { closeRequested(); }

  // Two-step: the first click arms an action, the second one runs it. A stray
  // click on a power button should never be able to kill the session.
  property string pending: ""

  PowerActions { id: power }
  readonly property var actions: power.actions

  function actionFor(key) {
    for (const a of actions) if (a.key === key) return a;
    return null;
  }

  // First click arms, second click on the same row runs it. Clicking anywhere
  // else (or esc) disarms.
  function choose(a) {
    if (a.instant || root.pending === a.key) {
      root.close();
      root.pending = "";
      powerProc.command = a.cmd;
      powerProc.running = true;
      return;
    }
    root.pending = a.key;
  }

  Process {
    id: powerProc
    running: false
  }

  PanelWindow {
    id: popup
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-powermenu"

    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Clicking the backdrop closes, and disarms anything pending.
    MouseArea {
      anchors.fill: parent
      onClicked: {
        root.pending = "";
        root.close();
      }

      Rectangle {
        anchors.fill: parent
        color: root.theme.bgOverlay
      }
    }

    Rectangle {
      id: box
      anchors.centerIn: parent
      width: 320
      height: 16 + layout.implicitHeight
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1
      focus: true

      Accessible.role: Accessible.Dialog
      Accessible.name: "Power menu"

      Keys.onEscapePressed: {
        root.pending = "";
        root.close();
      }

      ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        Text {
          Layout.fillWidth: true
          Layout.leftMargin: 4
          text: "Power"
          color: root.theme.accentPrimary
          font.pixelSize: 13
          font.family: root.font
          font.bold: true
        }

        Repeater {
          model: root.actions

          Rectangle {
            id: row
            required property var modelData

            readonly property bool armed: root.pending === modelData.key

            Layout.fillWidth: true
            Layout.preferredHeight: 46
            radius: 8
            color: armed ? (modelData.danger ? root.theme.accentRed : root.theme.accentPrimary)
                 : rowMouse.containsMouse ? root.theme.bgHover
                 : "transparent"
            border.width: 1
            border.color: armed ? "transparent" : root.theme.bgBorder

            Accessible.role: Accessible.MenuItem
            Accessible.name: modelData.label + (armed ? ", press again to confirm" : "")

            Behavior on color {
              ColorAnimation { duration: 120 }
            }

            ColumnLayout {
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              spacing: 0

              RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                  text: row.modelData.icon
                  color: row.armed ? root.theme.bgBase
                       : row.modelData.danger ? root.theme.accentRed
                       : root.theme.textPrimary
                  font.pixelSize: 18
                  font.family: root.font
                }

                Text {
                  Layout.fillWidth: true
                  text: row.modelData.label
                  color: row.armed ? root.theme.bgBase : root.theme.textPrimary
                  font.pixelSize: 13
                  font.family: root.font
                  font.bold: row.armed
                }
              }

              Text {
                Layout.fillWidth: true
                text: row.armed ? "Press again to confirm" : row.modelData.hint
                color: row.armed ? root.theme.bgBase : root.theme.textMuted
                opacity: row.armed ? 0.85 : 1
                font.pixelSize: 10
                font.family: root.font
                elide: Text.ElideRight
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.choose(row.modelData)
            }
          }
        }
      }
    }
  }
}
