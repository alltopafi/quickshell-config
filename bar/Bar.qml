import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../start-menu"
Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "Hack Nerd Font"
  property bool barVisible: true
  // Pill colour while hovered: surface tinted toward the accent so it is visible.
  readonly property color hoverColor: Qt.tint(theme.bgSurface, Qt.rgba(theme.accentPrimary.r, theme.accentPrimary.g, theme.accentPrimary.b, 0.25))

  // MPRIS active player
  property var activePlayer: {
    const players = Mpris.players.values;
    if (!players || players.length === 0) return null;
    for (const p of players) {
      if (p.playbackState === MprisPlaybackState.Playing) return p;
    }
    return players[0];
  }

  // How many workspaces are always listed, regardless of whether they are in
  // use. The rest only appear once you are on them or have a window open.
  property int alwaysShowWorkspaces: 4

  // Workspaces shown in the bar, as plain {id, focused, urgent, activate} so
  // that synthesised and real workspaces look identical to the Repeater.
  //
  // Hyprland's default workspace_destroy_policy is "destroy": an empty
  // workspace is removed the moment you leave it, so workspaces 1-4 do not
  // reliably exist in Hyprland.workspaces. They are therefore generated here
  // rather than filtered for. Switching to one is dispatched explicitly,
  // which also creates it.
  property var visibleWorkspaces: {
    const byId = {};
    const all = Hyprland.workspaces.values || [];
    for (const w of all) {
      // Skip special workspaces, which report a negative id.
      if (typeof w.id === "number" && w.id > 0) byId[w.id] = w;
    }

    const current = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
    const ids = Object.keys(byId).map(Number);
    let maxId = root.alwaysShowWorkspaces;
    for (const id of ids) if (id > maxId) maxId = id;

    const out = [];
    for (let id = 1; id <= maxId; id++) {
      const w = byId[id];
      const tops = w && w.toplevels && w.toplevels.values ? w.toplevels.values : null;
      const occupied = tops !== null ? tops.length > 0 : false;

      if (id > root.alwaysShowWorkspaces && id !== current && !occupied) continue;

      out.push({
        id: id,
        focused: id === current,
        urgent: !!(w && w.urgent),
        occupied: occupied,
        activate: w
          ? function () { w.activate(); }
          : function () { Hyprland.dispatch("hl.dsp.focus({workspace=" + id + "})"); }
      });
    }
    return out;
  }

  IpcHandler {
    target: "bar"
    function toggle(): void { root.barVisible = !root.barVisible; }
  }

  property bool statsOpen: false
  property bool batteryOpen: false
  property bool powerMenuOpen: false
  property bool networkOpen: false
  property bool calendarOpen: false
  property bool claudeUsageOpen: false
  property bool displayMenuOpen: false
  property bool startMenuOpen: false
  property bool wallpaperPickerOpen: false

  IpcHandler {
    target: "startmenu"
    function toggle(): void { root.startMenuOpen = !root.startMenuOpen; }
  }

  IpcHandler {
    target: "claudeusage"
    function toggle(): void { root.claudeUsageOpen = !root.claudeUsageOpen; }
  }

  IpcHandler {
    target: "display"
    function toggle(): void { root.displayMenuOpen = !root.displayMenuOpen; }
  }

  IpcHandler {
    target: "stats"
    function toggle(): void { root.statsOpen = !root.statsOpen; }
  }

  IpcHandler {
    target: "battery"
    function toggle(): void { root.batteryOpen = !root.batteryOpen; }
  }

  IpcHandler {
    target: "calendar"
    function toggle(): void { root.calendarOpen = !root.calendarOpen; }
  }

  IpcHandler {
    target: "network"
    function toggle(): void { root.networkOpen = !root.networkOpen; }
  }

  // "power" is what hyprland.lua's Super+Ctrl+P already called for.
  IpcHandler {
    target: "power"
    function toggle(): void { root.powerMenuOpen = !root.powerMenuOpen; }
  }

  // Single instance for all monitors, unlike the per-screen bar windows below.
  SystemStatsPopup {
    theme: root.theme
    font: root.font
    open: root.statsOpen
    onCloseRequested: root.statsOpen = false
  }

  BatteryPopup {
    theme: root.theme
    font: root.font
    open: root.batteryOpen
    onCloseRequested: root.batteryOpen = false
  }

  CalendarPopup {
    theme: root.theme
    font: root.font
    open: root.calendarOpen
    onCloseRequested: root.calendarOpen = false
  }

  NetworkMenu {
    theme: root.theme
    font: root.font
    open: root.networkOpen
    onCloseRequested: root.networkOpen = false
  }

  StartMenu {
    theme: root.theme
    font: root.font
    open: root.startMenuOpen
    onCloseRequested: root.startMenuOpen = false
    onWallpaperPickerRequested: {
      root.startMenuOpen = false;
      root.wallpaperPickerOpen = true;
    }
  }

  WallpaperPicker {
    theme: root.theme
    font: root.font
    open: root.wallpaperPickerOpen
    onCloseRequested: root.wallpaperPickerOpen = false
  }

  DisplayMenu {
    theme: root.theme
    font: root.font
    open: root.displayMenuOpen
    brightnessValue: root.brightnessValue
    hasBacklight: brightnessFile.path !== ""
    onCloseRequested: root.displayMenuOpen = false
    onBrightnessRequested: fraction => {
      brightnessSetProc.command = ["brightnessctl", "set", Math.max(1, Math.round(fraction * 100)) + "%"];
      brightnessSetProc.running = true;
    }
  }

  ClaudeUsagePopup {
    theme: root.theme
    font: root.font
    open: root.claudeUsageOpen
    onCloseRequested: root.claudeUsageOpen = false
  }

  PowerMenu {
    theme: root.theme
    font: root.font
    open: root.powerMenuOpen
    onCloseRequested: root.powerMenuOpen = false
  }

  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink]
  }

  // Brightness state
  property real brightnessValue: 0
  property real brightnessMax: 1

  FileView {
    id: brightnessFile
    path: ""
    watchChanges: true
    onFileChanged: brightnessReadProc.running = true
  }

  Process {
    id: brightnessReadProc
    command: ["brightnessctl", "get"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const val = parseInt(text.trim());
        if (!isNaN(val) && root.brightnessMax > 0)
          root.brightnessValue = val / root.brightnessMax;
      }
    }
  }

  Process {
    id: brightnessSetProc
    running: false
  }

  Process {
    id: backlightDiscovery
    command: ["sh", "-c", "p=$(ls -d /sys/class/backlight/*/brightness 2>/dev/null | head -1); [ -n \"$p\" ] && echo \"$p\" && cat \"${p%brightness}max_brightness\""]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n");
        if (lines.length >= 2) {
          const max = parseInt(lines[1]);
          if (!isNaN(max) && max > 0) root.brightnessMax = max;
          brightnessFile.path = lines[0];
          brightnessReadProc.running = true;
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.barVisible

      anchors {
        top: true
        left: true
        right: true
      }

      implicitHeight: 32
      color: root.theme.bgBase

      Item {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10

        // Left section: Time + Workspaces + Now Playing
        Row {
          id: leftSection
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8

          // Start menu
          Rectangle {
            height: 24
            width: 28
            radius: 12
            color: startMouse.containsMouse || root.startMenuOpen ? root.hoverColor : root.theme.bgSurface

            Accessible.role: Accessible.Button
            Accessible.name: "Start menu"

            Image {
              anchors.centerIn: parent
              width: 16
              height: 16
              source: "file:///usr/share/icons/cachyos.svg"
              sourceSize.width: 32
              sourceSize.height: 32
              fillMode: Image.PreserveAspectFit
            }

            MouseArea {
              id: startMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.startMenuOpen = !root.startMenuOpen
            }
          }

          // Time
          Rectangle {
            height: 24
            width: timeDate.width + 16
            radius: 12
            color: timeMouse.containsMouse ? root.hoverColor : root.theme.bgSurface

            Row {
              id: timeDate
              anchors.centerIn: parent
              spacing: 8

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: root.theme.accentPrimary
                font.pixelSize: 14
                font.family: root.font
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Time.timeString
                color: root.theme.textPrimary
                font.pixelSize: 12
                font.family: root.font
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Time.dateString
                color: root.theme.textSecondary
                font.pixelSize: 12
                font.family: root.font
              }
            }

            Accessible.role: Accessible.Button
            Accessible.name: "Date and time. Show calendar."

            MouseArea {
              id: timeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.calendarOpen = !root.calendarOpen
            }
          }

          // Workspaces
          Row {
            spacing: 4

            Repeater {
              model: root.visibleWorkspaces

              Rectangle {
                id: wsPill
                required property var modelData
                property bool urgentBlink: false

                Accessible.role: Accessible.Button
                Accessible.name: "Workspace " + modelData.id + (modelData.focused ? ", active" : "") + (modelData.urgent ? ", urgent" : "")

                width: modelData.focused ? 32 : 24
                height: 24
                radius: 12
                // Three states: active (accent), occupied but not active
                // (wsOccupied), and empty (bgSurface). Urgent blinking still
                // wins over the occupied colour so it stays visible.
                color: modelData.focused ? root.theme.accentPrimary :
                       modelData.urgent && urgentBlink ? root.theme.accentRed :
                       modelData.occupied ? root.theme.wsOccupied : root.theme.bgSurface

                Behavior on color {
                  ColorAnimation { duration: 150 }
                }

                SequentialAnimation {
                  loops: Animation.Infinite
                  running: wsPill.modelData.urgent && !wsPill.modelData.focused

                  PropertyAction { target: wsPill; property: "urgentBlink"; value: true }
                  PauseAnimation { duration: 500 }
                  PropertyAction { target: wsPill; property: "urgentBlink"; value: false }
                  PauseAnimation { duration: 500 }

                  onStopped: wsPill.urgentBlink = false
                }

                Text {
                  anchors.centerIn: parent
                  text: wsPill.modelData.id
                  color: wsPill.modelData.focused ? root.theme.bgBase : root.theme.textPrimary
                  font.pixelSize: 11
                  font.family: root.font
                  font.bold: wsPill.modelData.focused
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: wsPill.modelData.activate()
                }

                Behavior on width {
                  NumberAnimation { duration: 150 }
                }
              }
            }
          }

          // Now Playing
          Rectangle {
            height: 24
            width: nowPlayingContent.width + 16
            radius: 12
            color: npMouse.containsMouse ? root.hoverColor : root.theme.bgSurface
            visible: root.activePlayer !== null

            Accessible.role: Accessible.Button
            Accessible.name: {
              if (!root.activePlayer) return "No media";
              const artist = root.activePlayer.trackArtist || "";
              const title = root.activePlayer.trackTitle || "";
              return "Now playing: " + (artist ? artist + " - " : "") + title;
            }

            Row {
              id: nowPlayingContent
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: 8
              spacing: 6

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.activePlayer && root.activePlayer.isPlaying ? "󰐊" : "󰏤"
                color: root.theme.accentPrimary
                font.pixelSize: 14
                font.family: root.font
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                  if (!root.activePlayer) return "";
                  const artist = root.activePlayer.trackArtist || "";
                  const title = root.activePlayer.trackTitle || "";
                  return artist ? artist + " - " + title : title;
                }
                color: root.theme.textPrimary
                font.pixelSize: 11
                font.family: root.font
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 200)
              }
            }

            MouseArea {
              id: npMouse
              hoverEnabled: true
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.activePlayer.togglePlaying()
            }
          }
        }

        // Center section: Window Title (truly centered in bar)
        Item {
          anchors.centerIn: parent
          height: parent.height
          width: Math.max(0, parent.width - 2 * Math.max(leftSection.width, rightSection.width) - 32)

          Text {
            Accessible.role: Accessible.StaticText
            Accessible.name: "Active window: " + text
            text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
            color: root.theme.textPrimary
            font.pixelSize: 13
            font.family: root.font
            elide: Text.ElideRight
            width: Math.min(implicitWidth, parent.width)
            anchors.centerIn: parent
          }
        }

        // Right section: System Tray + System Info
        Row {
          id: rightSection
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8

          // System Tray
          // There's an issue that some tray not display correctly.
          // https://github.com/quickshell-mirror/quickshell/issues/26
          // https://github.com/quickshell-mirror/quickshell/pull/777
          Rectangle {
            implicitHeight: 24
            implicitWidth: trayIcons.implicitWidth + 4
            radius: 12
            color: root.theme.bgSurface

            RowLayout {
              id: trayIcons
              anchors.centerIn: parent
              spacing: 2

              Repeater {
                model: SystemTray.items

                MouseArea {
                  id: trayDelegate
                  required property SystemTrayItem modelData

                  Accessible.role: Accessible.Button
                  Accessible.name: modelData.tooltipTitle || modelData.title || "System tray item"

                  Layout.preferredWidth: 24
                  Layout.preferredHeight: 24

                  acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor

                  Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.hoverColor
                    visible: trayDelegate.containsMouse
                    z: -1
                  }

                  onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                      // The Claude app's icon opens the usage popup; its own
                      // menu stays on right-click.
                      if (modelData.id.indexOf("Claude") === 0) {
                        root.claudeUsageOpen = !root.claudeUsageOpen
                      } else if (modelData.hasMenu) {
                        menuAnchor.open()
                      } else {
                        modelData.activate()
                      }
                    } else if (mouse.button === Qt.RightButton) {
                      if (modelData.hasMenu) {
                        menuAnchor.open()
                      }
                    } else if (mouse.button === Qt.MiddleButton) {
                      modelData.secondaryActivate()
                    }
                  }

                  IconImage {
                    anchors.centerIn: parent
                    source: trayDelegate.modelData.icon
                    implicitSize: 16
                  }

                  QsMenuAnchor {
                    id: menuAnchor
                    menu: trayDelegate.modelData.menu

                    anchor.window: trayDelegate.QsWindow.window
                    anchor.adjustment: PopupAdjustment.Flip
                    anchor.onAnchoring: {
                      const window = trayDelegate.QsWindow.window;
                      const widgetRect = window.contentItem.mapFromItem(
                        trayDelegate, 0, trayDelegate.height,
                        trayDelegate.width, trayDelegate.height);
                      menuAnchor.anchor.rect = widgetRect;
                    }
                  }
                }
              }
            }
          }

          // Volume
          Rectangle {
            height: 24
            width: volContent.width + 12
            radius: 12
            color: volMouse.containsMouse ? root.hoverColor : root.theme.bgSurface

            Accessible.role: Accessible.StaticText
            Accessible.name: {
              const sink = Pipewire.defaultAudioSink;
              if (!sink || !sink.audio) return "Volume";
              if (sink.audio.muted) return "Volume: muted";
              return "Volume: " + Math.round(sink.audio.volume * 100) + "%";
            }

            Row {
              id: volContent
              anchors.centerIn: parent
              spacing: 6

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                  const sink = Pipewire.defaultAudioSink;
                  if (!sink || !sink.audio || sink.audio.muted || sink.audio.volume <= 0) return "󰖁";
                  if (sink.audio.volume < 0.33) return "󰕿";
                  if (sink.audio.volume < 0.66) return "󰖀";
                  return "󰕾";
                }
                color: {
                  const sink = Pipewire.defaultAudioSink;
                  if (!sink || !sink.audio || sink.audio.muted) return root.theme.textMuted;
                  return root.theme.accentPrimary;
                }
                font.pixelSize: 14
                font.family: root.font
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                  const sink = Pipewire.defaultAudioSink;
                  if (!sink || !sink.audio) return "–";
                  if (sink.audio.muted) return "Mute";
                  return Math.round(sink.audio.volume * 100) + "%";
                }
                color: root.theme.textPrimary
                font.pixelSize: 11
                font.family: root.font
              }
            }

            MouseArea {
              id: volMouse
              hoverEnabled: true
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton
              onClicked: {
                const sink = Pipewire.defaultAudioSink;
                if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
              }
              onWheel: (wheel) => {
                const sink = Pipewire.defaultAudioSink;
                if (!sink || !sink.audio) return;
                const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                sink.audio.volume = Math.max(0, Math.min(1.5, sink.audio.volume + delta));
              }
            }
          }

          // Displays: monitor list, scale and brightness
          Rectangle {
            height: 24
            width: brightContent.width + 12
            radius: 12
            color: brightMouse.containsMouse || root.displayMenuOpen ? root.hoverColor : root.theme.bgSurface

            Accessible.role: Accessible.Button
            Accessible.name: "Displays" + (brightnessFile.path !== "" ? ", brightness " + Math.round(root.brightnessValue * 100) + "%" : "")

            Row {
              id: brightContent
              anchors.centerIn: parent
              spacing: 6

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF0379)
                color: root.theme.accentOrange
                font.pixelSize: 14
                font.family: root.font
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: brightnessFile.path !== ""
                text: Math.round(root.brightnessValue * 100) + "%"
                color: root.theme.textPrimary
                font.pixelSize: 11
                font.family: root.font
              }
            }

            MouseArea {
              id: brightMouse
              hoverEnabled: true
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.displayMenuOpen = !root.displayMenuOpen
              onWheel: (wheel) => {
                brightnessSetProc.command = wheel.angleDelta.y > 0
                  ? ["brightnessctl", "set", "5%+"]
                  : ["brightnessctl", "set", "5%-"];
                brightnessSetProc.running = true;
              }
            }
          }

          // System Info
          Row {
            id: sysInfo

            readonly property color batteryColor: {
              if (SystemInfo.batteryCharging) return root.theme.accentGreen;
              if (SystemInfo.batteryLevelRaw > 20) return root.theme.batteryGood;
              if (SystemInfo.batteryLevelRaw > 10) return root.theme.batteryWarning;
              return root.theme.batteryCritical;
            }

            spacing: 4

            // CPU
            Rectangle {
              id: cpuPill
              height: 24
              width: cpuContent.width + 12
              radius: 12
              color: cpuMouse.containsMouse ? root.hoverColor : root.theme.bgSurface
              Accessible.role: Accessible.Button
              Accessible.name: "CPU: " + SystemInfo.cpuUsage + ". Show detailed system statistics."

              Row {
                id: cpuContent
                anchors.centerIn: parent
                spacing: 6

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰻠"
                  color: root.theme.accentOrange
                  font.pixelSize: 14
                  font.family: root.font
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: SystemInfo.cpuUsage
                  color: root.theme.textPrimary
                  font.pixelSize: 11
                  font.family: root.font
                }
              }

              MouseArea {
                id: cpuMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.statsOpen = !root.statsOpen
              }
            }

            // Network
            Rectangle {
              height: 24
              width: netContent.width + 12
              radius: 12
              color: netMouse.containsMouse ? root.hoverColor : root.theme.bgSurface
              Accessible.role: Accessible.Button
              Accessible.name: {
                if (SystemInfo.networkType === "ethernet") return "Network: Ethernet"
                if (SystemInfo.networkType === "wifi") return "Network: WiFi " + SystemInfo.networkInfo
                return "Network: Disconnected"
              }

              Row {
                id: netContent
                anchors.centerIn: parent
                spacing: 6

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: {
                    if (SystemInfo.networkType === "ethernet") return "󰈀"
                    if (SystemInfo.networkType === "wifi") return "󰖩"
                    return "󰖪"
                  }
                  color: SystemInfo.networkType === "disconnected" ? root.theme.textMuted : root.theme.accentGreen
                  font.pixelSize: 14
                  font.family: root.font
                }
              }

              MouseArea {
                id: netMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.networkOpen = !root.networkOpen
              }
            }
            // Battery
            Rectangle {
              id: battPill
              height: 24
              width: battContent.width + 12
              radius: 12
              color: battMouse.containsMouse ? root.hoverColor : root.theme.bgSurface
              Accessible.role: Accessible.Button
              Accessible.name: "Battery: " + SystemInfo.batteryLevel + ", " + SystemInfo.batteryStateText + ". Show battery and power details."

              Row {
                id: battContent
                anchors.centerIn: parent
                spacing: 6

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: SystemInfo.batteryIcon
                  color: sysInfo.batteryColor
                  font.pixelSize: 14
                  font.family: root.font
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: SystemInfo.batteryLevel
                  color: root.theme.textPrimary
                  font.pixelSize: 11
                  font.family: root.font
                }
              }

              MouseArea {
                id: battMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.batteryOpen = !root.batteryOpen
              }
            }
          }

          // Power menu
          Rectangle {
            id: powerBtn
            implicitHeight: 24
            implicitWidth: 24
            radius: 12
            color: powerMouse.containsMouse ? root.hoverColor : root.theme.bgSurface

            Accessible.role: Accessible.Button
            Accessible.name: "Power menu"

            Behavior on color {
              ColorAnimation { duration: 120 }
            }

            Text {
              anchors.centerIn: parent
              text: "󰐥"
              color: powerMouse.containsMouse ? root.theme.accentRed : root.theme.textSecondary
              font.pixelSize: 14
              font.family: root.font

              Behavior on color {
                ColorAnimation { duration: 120 }
              }
            }

            MouseArea {
              id: powerMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.powerMenuOpen = !root.powerMenuOpen
            }
          }
        }
      }

    }
  }
}
