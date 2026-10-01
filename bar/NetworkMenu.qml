import Quickshell
import Quickshell.Io
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

  function close(): void { closeRequested(); }

  // Glyphs (verified present in Hack Nerd Font): F05A9 md-wifi, F05AA md-wifi_off,
  // F033E md-lock, F0450 md-refresh, F012C md-check.
  readonly property string iconWifi: String.fromCodePoint(0xF05A9)
  readonly property string iconWifiOff: String.fromCodePoint(0xF05AA)
  readonly property string iconLock: String.fromCodePoint(0xF033E)
  readonly property string iconRefresh: String.fromCodePoint(0xF0450)
  readonly property string iconCheck: String.fromCodePoint(0xF012C)

  property var networks: []        // [{ssid, signal, secure, active}], active first
  property var known: ({})         // ssid -> true when a saved profile exists
  property string wifiDevice: ""
  property string selected: ""     // secured, unsaved network waiting for a password
  property string status: ""
  property bool busy: false

  readonly property bool connected: {
    for (const n of networks) if (n.active) return true;
    return false;
  }

  onOpenChanged: {
    if (open) {
      selected = "";
      status = "";
      refresh();
    }
  }

  function refresh(): void {
    devProc.running = true;
    knownProc.running = true;   // chains into listProc once the profiles are known
  }

  function rescan(): void {
    status = "Scanning…";
    rescanProc.running = true;
  }

  function run(cmd, label): void {
    busy = true;
    status = label;
    actionProc.command = cmd;
    actionProc.running = true;
  }

  function connectTo(n): void {
    if (busy) return;
    if (n.active) {
      if (root.wifiDevice !== "")
        run(["nmcli", "device", "disconnect", root.wifiDevice], "Disconnecting…");
      return;
    }
    if (root.known[n.ssid]) {
      run(["nmcli", "connection", "up", "id", n.ssid], "Connecting to " + n.ssid + "…");
    } else if (!n.secure) {
      run(["nmcli", "device", "wifi", "connect", n.ssid], "Connecting to " + n.ssid + "…");
    } else {
      root.selected = n.ssid;
      status = "";
    }
  }

  function submitPassword(pw): void {
    if (busy || root.selected === "" || pw === "") return;
    const ssid = root.selected;
    root.selected = "";
    // The password is visible in this process's argv for the duration of the call.
    run(["nmcli", "device", "wifi", "connect", ssid, "password", pw], "Connecting to " + ssid + "…");
  }

  Process {
    id: devProc
    command: ["nmcli", "-t", "-e", "no", "-f", "DEVICE,TYPE,STATE", "device"]
    stdout: StdioCollector {
      onStreamFinished: {
        let dev = "";
        for (const line of text.split("\n")) {
          const p = line.split(":");
          if (p[1] === "wifi" && (dev === "" || p[2] === "connected")) dev = p[0];
        }
        root.wifiDevice = dev;
      }
    }
  }

  Process {
    id: knownProc
    command: ["nmcli", "-t", "-e", "no", "-f", "NAME,TYPE", "connection", "show"]
    stdout: StdioCollector {
      onStreamFinished: {
        const k = {};
        for (const line of text.split("\n")) {
          const i = line.lastIndexOf(":");
          if (i > 0 && line.slice(i + 1) === "802-11-wireless") k[line.slice(0, i)] = true;
        }
        root.known = k;
        listProc.running = true;
      }
    }
  }

  Process {
    id: listProc
    command: ["nmcli", "-t", "-e", "no", "-f", "IN-USE,SIGNAL,SECURITY,SSID",
              "device", "wifi", "list", "--rescan", "no"]
    stdout: StdioCollector {
      onStreamFinished: {
        const best = {};
        for (const line of text.split("\n")) {
          // SSID is last because it may itself contain colons.
          const a = line.indexOf(":");
          const b = line.indexOf(":", a + 1);
          const c = line.indexOf(":", b + 1);
          if (c < 0) continue;
          const ssid = line.slice(c + 1);
          if (ssid === "") continue;
          const n = {
            ssid: ssid,
            active: line.slice(0, a) === "*",
            signal: parseInt(line.slice(a + 1, b)) || 0,
            secure: line.slice(b + 1, c) !== ""
          };
          const old = best[ssid];
          if (!old || (n.active && !old.active) || (n.active === old.active && n.signal > old.signal))
            best[ssid] = n;
        }
        const list = Object.values(best);
        list.sort((x, y) => (y.active - x.active) || (y.signal - x.signal));
        root.networks = list;
      }
    }
  }

  Process {
    id: rescanProc
    command: ["nmcli", "device", "wifi", "rescan"]
    onExited: {
      root.status = "";
      root.refresh();
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionErr }
    stdout: StdioCollector { id: actionOut }
    onExited: (code) => {
      root.busy = false;
      if (code === 0) {
        root.status = "";
        root.close();
      } else {
        const msg = (actionErr.text || actionOut.text).trim();
        root.status = msg !== "" ? msg : "Failed (exit " + code + ")";
        root.refresh();
      }
    }
  }

  PanelWindow {
    id: popup
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-networkmenu"

    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Clicking the backdrop closes.
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
      width: 340
      height: 24 + layout.implicitHeight
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1
      focus: true

      Accessible.role: Accessible.Dialog
      Accessible.name: "Wi-Fi networks"

      function dismiss(): void {
        if (root.selected !== "") {
          root.selected = "";
          box.forceActiveFocus();
        } else {
          root.close();
        }
      }

      Keys.onEscapePressed: box.dismiss()

      // Swallow clicks so they don't fall through to the backdrop.
      MouseArea { anchors.fill: parent }

      ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: 4

          Text {
            Layout.fillWidth: true
            text: "Wi-Fi"
            color: root.theme.accentPrimary
            font.pixelSize: 13
            font.family: root.font
            font.bold: true
          }

          Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            radius: 14
            color: scanMouse.containsMouse ? root.theme.bgHover : "transparent"

            Accessible.role: Accessible.Button
            Accessible.name: "Rescan networks"

            Text {
              anchors.centerIn: parent
              text: root.iconRefresh
              color: root.theme.textPrimary
              font.pixelSize: 16
              font.family: root.font
            }

            MouseArea {
              id: scanMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.rescan()
            }
          }
        }

        Text {
          Layout.fillWidth: true
          Layout.leftMargin: 4
          visible: root.networks.length === 0
          text: "No networks found"
          color: root.theme.textMuted
          font.pixelSize: 12
          font.family: root.font
        }

        ListView {
          id: list
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, 304)
          visible: root.networks.length > 0
          clip: true
          spacing: 4
          model: root.networks
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: row
            required property var modelData

            width: list.width
            height: 38
            radius: 8
            color: rowMouse.containsMouse ? root.theme.bgHover : "transparent"
            border.width: 1
            border.color: modelData.active ? root.theme.accentGreen : root.theme.bgBorder

            Accessible.role: Accessible.MenuItem
            Accessible.name: modelData.ssid + (modelData.active ? ", connected, click to disconnect" : "")

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              spacing: 10

              Text {
                text: root.iconWifi
                color: row.modelData.active ? root.theme.accentGreen : root.theme.textPrimary
                font.pixelSize: 16
                font.family: root.font
              }

              Text {
                Layout.fillWidth: true
                text: row.modelData.ssid
                color: root.theme.textPrimary
                font.pixelSize: 13
                font.family: root.font
                font.bold: row.modelData.active
                elide: Text.ElideRight
              }

              Text {
                visible: row.modelData.active && !rowMouse.containsMouse
                text: root.iconCheck
                color: root.theme.accentGreen
                font.pixelSize: 14
                font.family: root.font
              }

              Text {
                visible: row.modelData.active && rowMouse.containsMouse
                text: "Disconnect"
                color: root.theme.accentRed
                font.pixelSize: 11
                font.family: root.font
              }

              Text {
                visible: row.modelData.secure && !row.modelData.active
                text: root.iconLock
                color: root.theme.textMuted
                font.pixelSize: 12
                font.family: root.font
              }

              Text {
                text: row.modelData.signal + "%"
                color: root.theme.textMuted
                font.pixelSize: 10
                font.family: root.font
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.connectTo(row.modelData)
            }
          }
        }

        // Password prompt for secured networks without a saved profile.
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.selected !== ""
          spacing: 4

          onVisibleChanged: {
            if (visible) {
              pwField.text = "";
              pwField.forceActiveFocus();
            }
          }

          Text {
            Layout.leftMargin: 4
            text: "Password for " + root.selected
            color: root.theme.textSecondary
            font.pixelSize: 11
            font.family: root.font
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: 8
            color: root.theme.bgSurface
            border.width: 1
            border.color: root.theme.accentPrimary

            TextInput {
              id: pwField
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              verticalAlignment: TextInput.AlignVCenter
              echoMode: TextInput.Password
              color: root.theme.textPrimary
              font.pixelSize: 13
              font.family: root.font
              clip: true
              onAccepted: root.submitPassword(text)
              Keys.onEscapePressed: box.dismiss()
            }
          }

          Text {
            Layout.leftMargin: 4
            text: "Enter to connect · Esc to cancel"
            color: root.theme.textMuted
            font.pixelSize: 10
            font.family: root.font
          }
        }

        Text {
          Layout.fillWidth: true
          Layout.leftMargin: 4
          visible: root.status !== ""
          text: root.status
          color: root.status.endsWith("…") ? root.theme.textSecondary : root.theme.accentRed
          font.pixelSize: 11
          font.family: root.font
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
