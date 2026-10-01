import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Lists connected displays. The primary one (the monitor at 0,0) also gets
// scale buttons and the screen brightness slider.
Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "Hack Nerd Font"

  // Driven from the bar; the popup only reads it and asks to be closed.
  property bool open: false
  signal closeRequested

  // Brightness lives in the bar (it already tracks the backlight); the popup
  // reads it and asks for changes.
  property real brightnessValue: 0
  property bool hasBacklight: false
  signal brightnessRequested(real fraction)

  function close(): void { closeRequested(); }

  property var monitors: []

  readonly property var primary: {
    const on = monitors.filter(m => !m.disabled);
    return on.find(m => m.x === 0 && m.y === 0) || on[0] || null;
  }

  readonly property var scaleChoices: [1, 1.25, 1.5, 1.6, 1.75, 2, 2.5, 3]

  // Hyprland only accepts a scale that divides the resolution evenly.
  function validScales(m) {
    return scaleChoices.filter(s => {
      const w = m.width / s, h = m.height / s;
      return Math.abs(w - Math.round(w)) < 0.001 && Math.abs(h - Math.round(h)) < 0.001;
    });
  }

  function setScale(m, s): void {
    const lua = 'hl.monitor({ output = "' + m.name + '", mode = "' + m.width + "x" + m.height
              + "@" + m.refreshRate.toFixed(2) + '", position = "' + m.x + "x" + m.y
              + '", scale = ' + s + " })";
    applyProc.command = ["hyprctl", "eval", lua];
    applyProc.running = true;
  }

  function refresh(): void {
    if (!queryProc.running) queryProc.running = true;
  }

  onOpenChanged: if (open) refresh()

  Process {
    id: queryProc
    command: ["hyprctl", "-j", "monitors", "all"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.monitors = JSON.parse(text); } catch (e) { console.warn("DisplayMenu: bad hyprctl output"); }
      }
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() !== "ok") console.warn("DisplayMenu: scale change failed:", text.trim())
    }
    onRunningChanged: if (!running) settleTimer.restart()
  }

  // Give Hyprland a moment to finish re-laying out before re-reading.
  Timer {
    id: settleTimer
    interval: 400
    onTriggered: root.refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.open) return;
      if (["monitoradded", "monitorremoved", "configreloaded"].includes(event.name)) root.refresh();
    }
  }

  PanelWindow {
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-displays"

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
      width: 460
      height: 24 + layout.implicitHeight
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1
      focus: true

      Accessible.role: Accessible.Dialog
      Accessible.name: "Displays"

      Keys.onEscapePressed: root.close()

      MouseArea { anchors.fill: parent }

      ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
          Layout.fillWidth: true
          Text {
            text: String.fromCodePoint(0xF0379) + "  Displays"
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

        Repeater {
          model: root.monitors

          Rectangle {
            id: card
            required property var modelData
            readonly property bool isPrimary: root.primary !== null && modelData.name === root.primary.name
            readonly property var scales: root.validScales(modelData)

            Layout.fillWidth: true
            implicitHeight: cardCol.implicitHeight + 24
            radius: 12
            color: root.theme.bgSurface
            border.color: isPrimary ? root.theme.accentPrimary : root.theme.bgBorder
            border.width: 1

            ColumnLayout {
              id: cardCol
              anchors.fill: parent
              anchors.margins: 12
              spacing: 10

              RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                  text: String.fromCodePoint(0xF0379)
                  color: card.isPrimary ? root.theme.accentPrimary : root.theme.textSecondary
                  font.pixelSize: 22
                  font.family: root.font
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2

                  RowLayout {
                    spacing: 8
                    Text {
                      text: card.modelData.name
                      color: root.theme.textPrimary
                      font.pixelSize: 13
                      font.family: root.font
                      font.bold: true
                    }
                    Rectangle {
                      visible: card.isPrimary
                      width: primaryLabel.width + 12
                      height: 16
                      radius: 8
                      color: root.theme.accentPrimary
                      Text {
                        id: primaryLabel
                        anchors.centerIn: parent
                        text: "Primary"
                        color: root.theme.bgBase
                        font.pixelSize: 9
                        font.family: root.font
                        font.bold: true
                      }
                    }
                    Text {
                      visible: card.modelData.disabled
                      text: "disabled"
                      color: root.theme.textMuted
                      font.pixelSize: 10
                      font.family: root.font
                    }
                  }

                  Text {
                    Layout.fillWidth: true
                    text: card.modelData.description
                    color: root.theme.textMuted
                    font.pixelSize: 10
                    font.family: root.font
                    elide: Text.ElideRight
                  }

                  Text {
                    text: card.modelData.width + " × " + card.modelData.height
                        + " @ " + Math.round(card.modelData.refreshRate) + " Hz"
                        + "  ·  scale " + Number(card.modelData.scale.toFixed(2)) + "×"
                    color: root.theme.textSecondary
                    font.pixelSize: 11
                    font.family: root.font
                  }
                }
              }

              // ---- Scale (primary only) ----
              ColumnLayout {
                visible: card.isPrimary
                Layout.fillWidth: true
                spacing: 6

                Text {
                  text: "Scale"
                  color: root.theme.textSecondary
                  font.pixelSize: 12
                  font.family: root.font
                }

                Flow {
                  Layout.fillWidth: true
                  spacing: 6

                  Repeater {
                    model: card.scales

                    Rectangle {
                      id: scaleBtn
                      required property real modelData
                      readonly property bool active: Math.abs(card.modelData.scale - modelData) < 0.01

                      width: 52
                      height: 28
                      radius: 8
                      color: active ? root.theme.accentPrimary
                           : scaleMouse.containsMouse ? root.theme.bgHover : root.theme.bgBase
                      border.width: 1
                      border.color: active ? "transparent" : root.theme.bgBorder

                      Accessible.role: Accessible.Button
                      Accessible.name: "Scale " + modelData + "x" + (active ? ", current" : "")

                      Text {
                        anchors.centerIn: parent
                        text: Number(scaleBtn.modelData) + "×"
                        color: scaleBtn.active ? root.theme.bgBase : root.theme.textPrimary
                        font.pixelSize: 11
                        font.family: root.font
                        font.bold: scaleBtn.active
                      }

                      MouseArea {
                        id: scaleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!scaleBtn.active) root.setScale(card.modelData, scaleBtn.modelData)
                      }
                    }
                  }
                }
              }

              // ---- Brightness (primary only) ----
              ColumnLayout {
                visible: card.isPrimary && root.hasBacklight
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                  Layout.fillWidth: true
                  Text {
                    text: "Brightness"
                    color: root.theme.textSecondary
                    font.pixelSize: 12
                    font.family: root.font
                  }
                  Item { Layout.fillWidth: true }
                  Text {
                    text: Math.round(slider.shown * 100) + "%"
                    color: root.theme.accentOrange
                    font.pixelSize: 12
                    font.family: root.font
                    font.bold: true
                  }
                }

                Item {
                  id: slider
                  Layout.fillWidth: true
                  height: 22

                  property bool dragging: false
                  property real dragValue: 0
                  readonly property real shown: dragging ? dragValue : root.brightnessValue

                  Accessible.role: Accessible.Slider
                  Accessible.name: "Screen brightness"

                  function setFromX(x) {
                    dragValue = Math.max(0.01, Math.min(1, x / width));
                    sendTimer.restart();
                  }

                  // Throttled so dragging does not spawn a process per pixel.
                  Timer {
                    id: sendTimer
                    interval: 60
                    onTriggered: root.brightnessRequested(slider.dragValue)
                  }

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: root.theme.bgBase

                    Rectangle {
                      width: parent.width * slider.shown
                      height: parent.height
                      radius: 3
                      color: root.theme.accentOrange
                    }
                  }

                  Rectangle {
                    x: Math.max(0, Math.min(parent.width - width, parent.width * slider.shown - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 8
                    color: root.theme.textPrimary
                    border.color: root.theme.accentOrange
                    border.width: 2
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => { slider.dragging = true; slider.setFromX(mouse.x); }
                    onPositionChanged: mouse => { if (pressed) slider.setFromX(mouse.x); }
                    onReleased: {
                      sendTimer.stop();
                      root.brightnessRequested(slider.dragValue);
                      slider.dragging = false;
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          visible: root.monitors.length === 0
          Layout.alignment: Qt.AlignHCenter
          text: "No displays found"
          color: root.theme.textMuted
          font.pixelSize: 12
          font.family: root.font
        }
      }
    }
  }
}
