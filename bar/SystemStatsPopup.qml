import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "Hack Nerd Font"

  // Driven from the bar; the popup only reads it and asks to be closed.
  property bool open: false
  signal closeRequested

  function close(): void { closeRequested(); }

  function loadColor(pct) {
    if (pct >= 85) return root.theme.accentRed;
    if (pct >= 60) return root.theme.accentOrange;
    return root.theme.accentGreen;
  }

  function gib(bytes) {
    return (bytes / 1073741824).toFixed(1) + " GiB";
  }

  PanelWindow {
    id: popup
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-sysstats"

    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Backdrop, click anywhere to dismiss
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()

      Rectangle {
        anchors.fill: parent
        color: root.theme.bgOverlay
      }
    }

    Rectangle {
      id: box
      anchors.centerIn: parent
      width: 440
      height: 24 + layout.implicitHeight
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1
      focus: true

      Accessible.role: Accessible.Dialog
      Accessible.name: "System statistics"

      Keys.onEscapePressed: root.close()

      ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // Header
        RowLayout {
          Layout.fillWidth: true

          Text {
            text: "  System"
            color: root.theme.accentPrimary
            font.pixelSize: 14
            font.family: root.font
            font.bold: true
          }

          Item { Layout.fillWidth: true }

          Text {
            text: "esc to close"
            color: root.theme.textMuted
            font.pixelSize: 10
            font.family: root.font
          }
        }

        // ---- CPU ----
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 6

          RowLayout {
            Layout.fillWidth: true

            Text {
              text: "CPU"
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
            }

            Item { Layout.fillWidth: true }

            Text {
              text: SystemInfo.cpuPerCore.length > 0
                    ? SystemInfo.cpuPerCore.length + " cores"
                    : ""
              color: root.theme.textMuted
              font.pixelSize: 10
              font.family: root.font
            }

            Text {
              text: Math.round(SystemInfo.cpuPercent) + "%"
              color: root.loadColor(SystemInfo.cpuPercent)
              font.pixelSize: 14
              font.family: root.font
              font.bold: true
            }
          }

          // Aggregate bar
          Rectangle {
            Layout.fillWidth: true
            height: 6
            radius: 3
            color: root.theme.bgSurface

            Rectangle {
              height: parent.height
              radius: 3
              width: parent.width * Math.min(1, Math.max(0, SystemInfo.cpuPercent / 100))
              color: root.loadColor(SystemInfo.cpuPercent)

              Behavior on width {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
              }
              Behavior on color {
                ColorAnimation { duration: 220 }
              }
            }
          }

          // Per-core mini bars
          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 3

            Repeater {
              model: SystemInfo.cpuPerCore

              Rectangle {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 3
                color: root.theme.bgSurface
                clip: true

                Accessible.role: Accessible.StaticText
                Accessible.name: "Core " + (index + 1) + ": " + Math.round(modelData) + "%"

                Rectangle {
                  width: parent.width
                  height: parent.height * Math.min(1, Math.max(0, modelData / 100))
                  anchors.bottom: parent.bottom
                  color: root.loadColor(modelData)

                  Behavior on height {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                  }
                  Behavior on color {
                    ColorAnimation { duration: 220 }
                  }
                }
              }
            }
          }
        }

        // ---- Memory ----
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 6

          RowLayout {
            Layout.fillWidth: true

            Text {
              text: "Memory"
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
            }

            Item { Layout.fillWidth: true }

            Text {
              text: SystemInfo.memUsed > 0
                    ? root.gib(SystemInfo.memUsed) + " / " + root.gib(SystemInfo.memTotal)
                    : ""
              color: root.theme.textMuted
              font.pixelSize: 10
              font.family: root.font
            }

            Text {
              text: SystemInfo.memoryUsage
              color: root.loadColor(SystemInfo.memPercent)
              font.pixelSize: 14
              font.family: root.font
              font.bold: true
            }
          }

          Rectangle {
            Layout.fillWidth: true
            height: 6
            radius: 3
            color: root.theme.bgSurface

            Rectangle {
              height: parent.height
              radius: 3
              width: parent.width * Math.min(1, Math.max(0, SystemInfo.memPercent / 100))
              color: root.loadColor(SystemInfo.memPercent)

              Behavior on width {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
              }
              Behavior on color {
                ColorAnimation { duration: 220 }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.gib(SystemInfo.memAvailable) + " available"
            color: root.theme.textMuted
            font.pixelSize: 10
            font.family: root.font
          }
        }

        // ---- Swap ----
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 6
          visible: SystemInfo.swapTotal > 0

          RowLayout {
            Layout.fillWidth: true

            Text {
              text: "Swap"
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
            }

            Item { Layout.fillWidth: true }

            Text {
              text: SystemInfo.swapTotal > 0
                    ? root.gib(SystemInfo.swapUsed) + " / " + root.gib(SystemInfo.swapTotal)
                    : ""
              color: root.theme.textMuted
              font.pixelSize: 10
              font.family: root.font
            }

            Text {
              text: SystemInfo.swapPercent.toFixed(1) + "%"
              color: root.loadColor(SystemInfo.swapPercent)
              font.pixelSize: 14
              font.family: root.font
              font.bold: true
            }
          }

          Rectangle {
            Layout.fillWidth: true
            height: 6
            radius: 3
            color: root.theme.bgSurface

            Rectangle {
              height: parent.height
              radius: 3
              width: parent.width * Math.min(1, Math.max(0, SystemInfo.swapPercent / 100))
              color: root.loadColor(SystemInfo.swapPercent)

              Behavior on width {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
              }
              Behavior on color {
                ColorAnimation { duration: 220 }
              }
            }
          }
        }
      }
    }
  }
}
