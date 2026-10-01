import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../notifications"

// Notification history plus do-not-disturb, opened from the bar's bell.
Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "Hack Nerd Font"

  // Driven from the bar; the popup only reads it and asks to be closed.
  property bool open: false
  signal closeRequested

  function close(): void { closeRequested(); }

  property real now: Date.now()

  onOpenChanged: if (open) { now = Date.now(); NotificationService.unread = 0; }

  Timer {
    interval: 30000
    running: root.open
    repeat: true
    onTriggered: root.now = Date.now()
  }

  function ago(ms) {
    const m = Math.floor((root.now - ms) / 60000);
    if (m < 1) return "now";
    if (m < 60) return m + "m ago";
    const h = Math.floor(m / 60);
    if (h < 24) return h + "h ago";
    return Math.floor(h / 24) + "d ago";
  }

  PanelWindow {
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-notification-center"

    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
      Rectangle { anchors.fill: parent; color: root.theme.bgOverlay }
    }

    Rectangle {
      id: box
      anchors.centerIn: parent
      width: 440
      height: Math.min(parent.height - 80, 24 + layout.implicitHeight)
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1
      focus: true

      Accessible.role: Accessible.Dialog
      Accessible.name: "Notifications"

      Keys.onEscapePressed: root.close()

      MouseArea { anchors.fill: parent }

      ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: String.fromCodePoint(0xF009A) + "  Notifications"
            color: root.theme.accentPrimary
            font.pixelSize: 14
            font.family: root.font
            font.bold: true
          }

          Item { Layout.fillWidth: true }

          // Do not disturb
          Rectangle {
            readonly property bool on: NotificationService.doNotDisturb
            height: 26
            width: dndRow.width + 16
            radius: 13
            color: on ? root.theme.accentOrange : dndMouse.containsMouse ? root.theme.bgHover : root.theme.bgSurface

            Accessible.role: Accessible.CheckBox
            Accessible.name: "Do not disturb"
            Accessible.checked: on

            Row {
              id: dndRow
              anchors.centerIn: parent
              spacing: 6
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF009B)
                color: parent.parent.on ? root.theme.bgBase : root.theme.textSecondary
                font.pixelSize: 12
                font.family: root.font
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Do not disturb"
                color: parent.parent.on ? root.theme.bgBase : root.theme.textSecondary
                font.pixelSize: 11
                font.family: root.font
              }
            }

            MouseArea {
              id: dndMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: NotificationService.doNotDisturb = !NotificationService.doNotDisturb
            }
          }

          // Clear all
          Rectangle {
            visible: NotificationService.history.length > 0
            height: 26
            width: clearLabel.width + 16
            radius: 13
            color: clearMouse.containsMouse ? root.theme.bgHover : root.theme.bgSurface

            Accessible.role: Accessible.Button
            Accessible.name: "Clear all notifications"

            Text {
              id: clearLabel
              anchors.centerIn: parent
              text: "Clear all"
              color: root.theme.textSecondary
              font.pixelSize: 11
              font.family: root.font
            }

            MouseArea {
              id: clearMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: NotificationService.clearHistory()
            }
          }
        }

        ListView {
          id: list
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredHeight: Math.min(contentHeight, 420)
          clip: true
          spacing: 8
          boundsBehavior: Flickable.StopAtBounds
          model: NotificationService.history

          delegate: Rectangle {
            id: item
            required property var modelData
            width: list.width
            implicitHeight: itemCol.implicitHeight + 20
            height: implicitHeight
            radius: 10
            color: root.theme.bgSurface
            border.width: 1
            border.color: modelData.urgency === 2 ? root.theme.accentRed : root.theme.bgBorder

            ColumnLayout {
              id: itemCol
              anchors.fill: parent
              anchors.margins: 10
              spacing: 3

              RowLayout {
                Layout.fillWidth: true
                Text {
                  Layout.fillWidth: true
                  text: item.modelData.appName + "  ·  " + root.ago(item.modelData.time)
                  color: root.theme.textMuted
                  font.pixelSize: 10
                  font.family: root.font
                  elide: Text.ElideRight
                }
                Text {
                  text: String.fromCodePoint(0xF0156)
                  color: dismissMouse.containsMouse ? root.theme.accentRed : root.theme.textMuted
                  font.pixelSize: 12
                  font.family: root.font
                  Accessible.role: Accessible.Button
                  Accessible.name: "Remove notification"
                  MouseArea {
                    id: dismissMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.removeFromHistory(item.modelData)
                  }
                }
              }

              Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: item.modelData.summary
                color: root.theme.textPrimary
                font.pixelSize: 12
                font.family: root.font
                font.bold: true
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: item.modelData.body
                textFormat: Text.PlainText
                color: root.theme.textSecondary
                font.pixelSize: 11
                font.family: root.font
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
              }
            }
          }
        }

        Text {
          visible: NotificationService.history.length === 0
          Layout.alignment: Qt.AlignHCenter
          Layout.topMargin: 8
          Layout.bottomMargin: 8
          text: NotificationService.doNotDisturb ? "Do not disturb is on. New notifications are hidden." : "No notifications"
          color: root.theme.textMuted
          font.pixelSize: 12
          font.family: root.font
        }
      }
    }
  }
}
