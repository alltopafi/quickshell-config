import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Shows Claude plan usage. The numbers come from ~/Git/claude-usage/claude-usage.sh,
// which prints JSON for the 5 hour and 7 day windows. It runs when the popup
// opens and then once a minute while it stays open.
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

  // Script that prints { five_hour: {...}, seven_day: {...} } (or { error }).
  property string scriptPath: Quickshell.env("HOME") + "/Git/claude-usage/claude-usage.sh"

  property var data: null          // parsed script output
  property bool loading: false
  property real updated: 0         // epoch seconds of the last good reading
  property real now: Date.now() / 1000

  function refresh(): void {
    if (usageProc.running) return;
    loading = true;
    usageProc.running = true;
  }

  onOpenChanged: {
    if (!open) return;
    now = Date.now() / 1000;
    refresh();
  }

  Process {
    id: usageProc
    command: ["bash", root.scriptPath]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.loading = false;
        try {
          root.data = JSON.parse(text);
          if (!root.data.error) root.updated = Date.now() / 1000;
        } catch (e) {
          root.data = { error: "Could not read the usage script's output" };
        }
        root.now = Date.now() / 1000;
      }
    }
  }

  // Keeps the countdowns moving while the popup is open.
  Timer {
    interval: 30000
    running: root.open
    repeat: true
    onTriggered: root.now = Date.now() / 1000
  }

  // Re-run the script while the popup is open so the numbers stay current.
  Timer {
    interval: 60000
    running: root.open
    repeat: true
    onTriggered: root.refresh()
  }

  function loadColor(pct) {
    if (pct >= 85) return root.theme.accentRed;
    if (pct >= 60) return root.theme.accentOrange;
    return root.theme.accentGreen;
  }

  function window(key) {
    const w = data && !data.error ? data[key] : null;
    return w && typeof w.utilization_percent === "number" ? w : null;
  }

  function resetEpoch(w) {
    return Date.parse(w.resets_at) / 1000;
  }

  function num(n) {
    return Number(n).toLocaleString(Qt.locale(), "f", 0);
  }

  function duration(secs) {
    const m = Math.max(0, Math.round(secs / 60));
    const d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60), mm = m % 60;
    if (d > 0) return d + "d " + h + "h";
    if (h > 0) return h + "h " + mm + "m";
    return mm + "m";
  }

  function clock(epoch) {
    return Qt.formatDateTime(new Date(epoch * 1000), "ddd h:mm AP");
  }

  PanelWindow {
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-claude-usage"

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
      width: 400
      height: 24 + layout.implicitHeight
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1
      focus: true

      Accessible.role: Accessible.Dialog
      Accessible.name: "Claude usage"

      Keys.onEscapePressed: root.close()

      MouseArea { anchors.fill: parent }

      ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "Claude usage"
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
          model: [
            { key: "five_hour", label: "Current session (5 hour)" },
            { key: "seven_day", label: "Weekly (7 day)" }
          ]

          ColumnLayout {
            id: win
            required property var modelData
            readonly property var w: root.window(modelData.key)
            // A window past its reset time has been reset, but we have no new
            // reading for it until the next Claude Code message.
            readonly property bool expired: w !== null && root.resetEpoch(w) <= root.now
            readonly property real pct: w !== null && !expired ? Math.min(100, w.utilization_percent) : 0

            Layout.fillWidth: true
            spacing: 6

            RowLayout {
              Layout.fillWidth: true
              Text {
                text: win.modelData.label
                color: root.theme.textSecondary
                font.pixelSize: 12
                font.family: root.font
              }
              Item { Layout.fillWidth: true }
              Text {
                text: win.w === null ? "—" : win.expired ? "reset" : Math.round(win.pct) + "%"
                color: win.w === null ? root.theme.textMuted : root.loadColor(win.pct)
                font.pixelSize: 12
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
                width: parent.width * win.pct / 100
                height: parent.height
                radius: 4
                color: root.loadColor(win.pct)
              }
            }

            Text {
              Layout.fillWidth: true
              text: win.w === null ? "No data for this window yet"
                  : win.expired ? "Window has reset. Reopen to refresh."
                  : "Resets in " + root.duration(root.resetEpoch(win.w) - root.now) + "  (" + root.clock(root.resetEpoch(win.w)) + ")"
              color: root.theme.textMuted
              font.pixelSize: 10
              font.family: root.font
              wrapMode: Text.WordWrap
            }

            Text {
              Layout.fillWidth: true
              visible: win.w !== null && !win.expired
              text: win.w === null ? "" : root.num(win.w.tokens_used) + " tokens used"
                  + (win.w.tokens_remaining_estimated !== null && win.w.tokens_remaining_estimated !== undefined
                     ? "  ·  ~" + root.num(win.w.tokens_remaining_estimated) + " left" : "")
              color: root.theme.textMuted
              font.pixelSize: 10
              font.family: root.font
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.data && root.data.error ? root.data.error
                : root.data === null ? (root.loading ? "Loading usage…" : "No usage data yet")
                : "Updated " + root.duration(root.now - root.updated) + " ago" + (root.loading ? " · refreshing…" : "")
          color: root.theme.textMuted
          font.pixelSize: 10
          font.family: root.font
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
