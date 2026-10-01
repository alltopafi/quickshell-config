import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Shows Claude plan usage. The numbers come from the Claude Code status line,
// which claude-usage/capture.sh saves to a cache file, so they are only as
// fresh as your last Claude Code message.
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

  property var data: null          // { updated, rate_limits: { five_hour, seven_day } }
  property real now: Date.now() / 1000

  onOpenChanged: if (open) { now = Date.now() / 1000; usageFile.reload(); }

  FileView {
    id: usageFile
    path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/quickshell/claude-usage.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.data = JSON.parse(text()); } catch (e) { root.data = null; }
    }
    onLoadFailed: root.data = null
  }

  // Keeps the countdowns moving while the popup is open.
  Timer {
    interval: 30000
    running: root.open
    repeat: true
    onTriggered: root.now = Date.now() / 1000
  }

  function loadColor(pct) {
    if (pct >= 85) return root.theme.accentRed;
    if (pct >= 60) return root.theme.accentOrange;
    return root.theme.accentGreen;
  }

  function window(key) {
    const w = data && data.rate_limits ? data.rate_limits[key] : null;
    return w && typeof w.used_percentage === "number" ? w : null;
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
            readonly property bool expired: w !== null && w.resets_at <= root.now
            readonly property real pct: w !== null && !expired ? Math.min(100, w.used_percentage) : 0

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
                  : win.expired ? "Window has reset. Send a message in Claude Code to refresh."
                  : "Resets in " + root.duration(win.w.resets_at - root.now) + "  (" + root.clock(win.w.resets_at) + ")"
              color: root.theme.textMuted
              font.pixelSize: 10
              font.family: root.font
              wrapMode: Text.WordWrap
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.data === null
                ? "No usage recorded yet. It appears after your next Claude Code message (Pro or Max plan)."
                : "Updated " + root.duration(root.now - root.data.updated) + " ago, from your last Claude Code message"
          color: root.theme.textMuted
          font.pixelSize: 10
          font.family: root.font
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
