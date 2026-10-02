import Quickshell
import Quickshell.Services.UPower
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

  // Where the clicked bar button sits (window x); the popup hangs under it.
  property real anchorX: 100000

  function close(): void { closeRequested(); }

  onOpenChanged: if (open) SystemInfo.refreshBatteryCycles()

  readonly property bool onAC: SystemInfo.acSource !== ""

  // UPower: 0 = unknown, negative = effectively never.
  function duration(seconds) {
    if (!(seconds > 0)) return "unknown";
    const s = Math.round(seconds);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (h <= 0) return m + " m";
    return h + " h " + (m > 0 ? m + " m" : "");
  }

  function wattText() {
    const w = SystemInfo.batteryWatts;
    if (!(w > 0.05)) return "idle";
    return w.toFixed(1) + " W";
  }

  function sourceText() {
    if (!root.onAC) return "Battery";
    const s = SystemInfo.acSource.toLowerCase();
    if (s.startsWith("ac")) return "AC adapter";
    if (s.includes("usb")) return "USB-C";
    return "External";
  }

  function levelColor(pct) {
    if (pct <= 10) return root.theme.accentRed;
    if (pct <= 20) return root.theme.batteryWarning;
    return root.theme.accentGreen;
  }

  // Glyph names verified against the installed font: F032A md-leaf,
  // F04C5 md-speedometer, F0241 md-flash.
  readonly property var modes: [
    { key: "PowerSaver", label: "Power saver", icon: "\uF032A" },
    { key: "Balanced", label: "Balanced", icon: "\uF04C5" },
    { key: "Performance", label: "Performance", icon: "\uF0241" }
  ]

  function modeFor(key) {
    switch (key) {
      case "PowerSaver": return PowerProfile.PowerSaver;
      case "Balanced": return PowerProfile.Balanced;
      case "Performance": return PowerProfile.Performance;
    }
    return PowerProfile.Balanced;
  }

  function isActive(entry) {
    return PowerProfiles.profile === root.modeFor(entry.key);
  }

  function degradationText() {
    switch (PowerProfiles.degradationReason) {
      case PerformanceDegradationReason.LapDetected: return "Laptop mode";
      case PerformanceDegradationReason.HighTemperature: return "Thermally limited";
      default: return "";
    }
  }

  PanelWindow {
    id: popup
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-battery"

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
    }

    Rectangle {
      id: box
      x: Math.max(12, Math.min(parent.width - width - 12, root.anchorX - width / 2))
      y: 44
      width: 420
      height: 28 + layout.implicitHeight
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1
      focus: true

      Accessible.role: Accessible.Dialog
      Accessible.name: "Battery and power"

      Keys.onEscapePressed: root.close()

      ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // ---- Header ----
        RowLayout {
          Layout.fillWidth: true

          Text {
            text: "  Battery"
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

        // ---- Big level + state ----
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 8

          RowLayout {
            Layout.fillWidth: true

            Text {
              text: SystemInfo.batteryIcon
              color: root.levelColor(SystemInfo.batteryLevelRaw)
              font.pixelSize: 30
              font.family: root.font
            }

            Item { Layout.fillWidth: true }

            Text {
              text: SystemInfo.batteryStateText
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
            }

            Text {
              text: SystemInfo.batteryLevel
              color: root.levelColor(SystemInfo.batteryLevelRaw)
              font.pixelSize: 20
              font.family: root.font
              font.bold: true
            }
          }

          Rectangle {
            Layout.fillWidth: true
            height: 8
            radius: 4
            color: root.theme.bgSurface

            Rectangle {
              height: parent.height
              radius: 4
              width: parent.width * Math.min(1, Math.max(0, SystemInfo.batteryLevelRaw / 100))
              color: root.levelColor(SystemInfo.batteryLevelRaw)

              Behavior on width {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
              }
              Behavior on color {
                ColorAnimation { duration: 260 }
              }
            }
          }
        }

        // ---- Detail rows ----
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 7

          // Power flow
          RowLayout {
            Layout.fillWidth: true

            Text {
              text: SystemInfo.batteryCharging ? "Charging at" : "Discharging at"
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
              Layout.fillWidth: true
            }

            Text {
              text: root.wattText()
              color: SystemInfo.batteryWatts > 0.05
                     ? (SystemInfo.batteryCharging ? root.theme.accentGreen : root.theme.accentOrange)
                     : root.theme.textMuted
              font.pixelSize: 12
              font.family: root.font
            }
          }

          // Time
          RowLayout {
            Layout.fillWidth: true

            Text {
              text: SystemInfo.batteryCharging ? "Time to full" : "Time remaining"
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
              Layout.fillWidth: true
            }

            Text {
              text: root.duration(SystemInfo.batteryCharging
                                  ? SystemInfo.batteryTimeToFull
                                  : SystemInfo.batteryTimeToEmpty)
              color: root.theme.textPrimary
              font.pixelSize: 12
              font.family: root.font
            }
          }

          // Power source
          RowLayout {
            Layout.fillWidth: true

            Text {
              text: "Power source"
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
              Layout.fillWidth: true
            }

            Text {
              text: root.sourceText()
              color: root.theme.textPrimary
              font.pixelSize: 12
              font.family: root.font
            }
          }

          // Energy, only meaningful when the pack reports Wh
          RowLayout {
            Layout.fillWidth: true
            visible: SystemInfo.batteryEnergyFull > 0

            Text {
              text: "Energy stored"
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
              Layout.fillWidth: true
            }

            Text {
              text: SystemInfo.batteryEnergy.toFixed(1) + " / "
                    + SystemInfo.batteryEnergyFull.toFixed(1) + " Wh"
              color: root.theme.textPrimary
              font.pixelSize: 12
              font.family: root.font
            }
          }

          // Charge cycles, when the pack reports them
          RowLayout {
            Layout.fillWidth: true
            visible: SystemInfo.batteryCycles >= 0

            Text {
              text: "Charge cycles"
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
              Layout.fillWidth: true
            }

            Text {
              text: SystemInfo.batteryCycles
              color: root.theme.textPrimary
              font.pixelSize: 12
              font.family: root.font
            }
          }
        }

        // ---- Power mode ----
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 7

          RowLayout {
            Layout.fillWidth: true

            Text {
              text: "Power mode"
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
            }

            Item { Layout.fillWidth: true }

            Text {
              text: root.degradationText()
              visible: text !== ""
              color: root.theme.accentOrange
              font.pixelSize: 10
              font.family: root.font
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
              model: root.modes

              Rectangle {
                id: modeButton
                required property var modelData

                readonly property bool active: root.isActive(modelData)
                readonly property bool performanceBlocked:
                  modelData.key === "Performance" && !PowerProfiles.hasPerformanceProfile

                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: 8
                color: active ? root.theme.accentPrimary
                     : modeMouse.containsMouse ? root.theme.bgHover
                     : root.theme.bgSurface
                border.width: 1
                border.color: active ? root.theme.accentPrimary : root.theme.bgBorder
                opacity: performanceBlocked ? 0.5 : 1

                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.label + (active ? ", active" : "")
                Accessible.checked: active

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: modeButton.modelData.icon
                        color: modeButton.active ? root.theme.bgBase : root.theme.textSecondary
                        font.pixelSize: 13
                        font.family: root.font
                    }

                    Text {
                        text: modeButton.modelData.label
                        color: modeButton.active ? root.theme.bgBase : root.theme.textPrimary
                        font.pixelSize: 11
                        font.family: root.font
                        font.bold: modeButton.active
                    }
                }

                Behavior on color {
                  ColorAnimation { duration: 140 }
                }

                MouseArea {
                  id: modeMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modeButton.performanceBlocked) return;
                    PowerProfiles.profile = root.modeFor(modeButton.modelData.key);
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
