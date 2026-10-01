import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
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

  readonly property var adapter: Bluetooth.defaultAdapter

  // Glyphs verified in Hack Nerd Font: F00AF md-bluetooth, F0450 md-refresh.
  readonly property string iconBluetooth: String.fromCodePoint(0xF00AF)

  // Scanning keeps the radio busy, so only do it while the menu is open.
  onOpenChanged: {
    if (!adapter) return;
    if (!open) adapter.discovering = false;
  }

  // Connected first, then paired, then the rest, each group by name.
  readonly property var devices: {
    const all = Bluetooth.devices ? Bluetooth.devices.values : [];
    const shown = all.filter(d => d.paired || d.connected || (adapter && adapter.discovering));
    return shown.slice().sort((a, b) => {
      const ra = a.connected ? 0 : a.paired ? 1 : 2;
      const rb = b.connected ? 0 : b.paired ? 1 : 2;
      if (ra !== rb) return ra - rb;
      return (a.name || a.address).localeCompare(b.name || b.address);
    });
  }

  function statusText(d) {
    if (d.pairing) return "Pairing…";
    if (d.state === BluetoothDeviceState.Connecting) return "Connecting…";
    if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…";
    if (d.connected) return "Connected";
    if (d.paired) return "Paired";
    return "Available";
  }

  function activate(d): void {
    if (d.connected) d.disconnect();
    else if (d.paired) d.connect();
    else d.pair();
  }

  PanelWindow {
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-bluetooth"

    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Rectangle {
      id: box
      x: Math.max(12, Math.min(parent.width - width - 12, root.anchorX - width / 2))
      y: 44
      width: 420
      height: Math.min(parent.height - 80, 24 + layout.implicitHeight)
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1
      focus: true

      Accessible.role: Accessible.Dialog
      Accessible.name: "Bluetooth"

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
            text: root.iconBluetooth + "  Bluetooth"
            color: root.theme.accentPrimary
            font.pixelSize: 14
            font.family: root.font
            font.bold: true
          }

          Item { Layout.fillWidth: true }

          // Scan
          Rectangle {
            visible: root.adapter !== null && root.adapter.enabled
            readonly property bool on: root.adapter !== null && root.adapter.discovering
            height: 26
            width: scanRow.width + 16
            radius: 13
            color: on ? root.theme.accentPrimary : scanMouse.containsMouse ? root.theme.bgHover : root.theme.bgSurface

            Accessible.role: Accessible.CheckBox
            Accessible.name: "Scan for devices"
            Accessible.checked: on

            Row {
              id: scanRow
              anchors.centerIn: parent
              spacing: 6
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF0450)
                color: parent.parent.on ? root.theme.bgBase : root.theme.textSecondary
                font.pixelSize: 12
                font.family: root.font
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.on ? "Scanning…" : "Scan"
                color: parent.parent.on ? root.theme.bgBase : root.theme.textSecondary
                font.pixelSize: 11
                font.family: root.font
              }
            }

            MouseArea {
              id: scanMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.adapter.discovering = !root.adapter.discovering
            }
          }

          // Power switch
          Rectangle {
            visible: root.adapter !== null
            readonly property bool on: root.adapter !== null && root.adapter.enabled
            width: 44
            height: 24
            radius: 12
            color: on ? root.theme.accentPrimary : root.theme.bgSurface
            border.width: 1
            border.color: on ? "transparent" : root.theme.bgBorder

            Accessible.role: Accessible.CheckBox
            Accessible.name: "Bluetooth power"
            Accessible.checked: on

            Rectangle {
              width: 18
              height: 18
              radius: 9
              y: 3
              x: parent.on ? parent.width - width - 3 : 3
              color: parent.on ? root.theme.bgBase : root.theme.textSecondary
              Behavior on x { NumberAnimation { duration: 120 } }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.adapter.enabled = !root.adapter.enabled
            }
          }
        }

        ListView {
          id: list
          visible: root.adapter !== null && root.adapter.enabled
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, 360)
          clip: true
          spacing: 6
          boundsBehavior: Flickable.StopAtBounds
          model: root.devices

          delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool busy: modelData.pairing
              || modelData.state === BluetoothDeviceState.Connecting
              || modelData.state === BluetoothDeviceState.Disconnecting

            width: list.width
            height: 48
            radius: 10
            color: rowMouse.containsMouse ? root.theme.bgHover : root.theme.bgSurface
            border.width: 1
            border.color: modelData.connected ? root.theme.accentPrimary : root.theme.bgBorder

            Accessible.role: Accessible.Button
            Accessible.name: (modelData.name || modelData.address) + ", " + root.statusText(modelData)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              spacing: 10

              Text {
                text: String.fromCodePoint(modelData.connected ? 0xF00B1 : 0xF00AF)
                color: row.modelData.connected ? root.theme.accentPrimary : root.theme.textMuted
                font.pixelSize: 18
                font.family: root.font
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                  Layout.fillWidth: true
                  text: row.modelData.name || row.modelData.address
                  color: root.theme.textPrimary
                  font.pixelSize: 12
                  font.family: root.font
                  elide: Text.ElideRight
                }
                Text {
                  text: root.statusText(row.modelData)
                    + (row.modelData.batteryAvailable
                       ? "  ·  " + Math.round(row.modelData.battery <= 1 ? row.modelData.battery * 100 : row.modelData.battery) + "%"
                       : "")
                  color: root.theme.textMuted
                  font.pixelSize: 10
                  font.family: root.font
                }
              }

              // Forget a paired device
              Text {
                visible: row.modelData.paired && !row.busy
                text: "Forget"
                color: forgetMouse.containsMouse ? root.theme.accentRed : root.theme.textMuted
                font.pixelSize: 10
                font.family: root.font
                Accessible.role: Accessible.Button
                Accessible.name: "Forget " + (row.modelData.name || row.modelData.address)
                MouseArea {
                  id: forgetMouse
                  anchors.fill: parent
                  anchors.margins: -6
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: row.modelData.forget()
                }
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              z: -1
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: !row.busy
              onClicked: root.activate(row.modelData)
            }
          }
        }

        Text {
          visible: root.adapter === null
          Layout.alignment: Qt.AlignHCenter
          text: "No Bluetooth adapter found"
          color: root.theme.textMuted
          font.pixelSize: 12
          font.family: root.font
        }

        Text {
          visible: root.adapter !== null && !root.adapter.enabled
          Layout.alignment: Qt.AlignHCenter
          text: "Bluetooth is off"
          color: root.theme.textMuted
          font.pixelSize: 12
          font.family: root.font
        }

        Text {
          visible: root.adapter !== null && root.adapter.enabled && list.count === 0
          Layout.alignment: Qt.AlignHCenter
          text: "No paired devices. Press Scan to find some."
          color: root.theme.textMuted
          font.pixelSize: 12
          font.family: root.font
        }
      }
    }
  }
}
