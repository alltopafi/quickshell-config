import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "fuzzy.js" as Fuzzy

Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "Hack Nerd Font"

  property bool open: false
  signal closeRequested

  readonly property string dir: Quickshell.env("HOME") + "/Pictures/wallpapers"
  readonly property string script: Quickshell.shellDir + "/start-menu/set-wallpaper.sh"

  property var wallpapers: []
  property string query: ""
  property string current: ""
  property string error: ""

  readonly property var results: Fuzzy.filter(wallpapers, query, p => p.split("/").pop())

  onOpenChanged: {
    if (!open) return;
    query = "";
    error = "";
    rescan();
    Qt.callLater(() => searchInput.forceActiveFocus());
  }

  function rescan(): void {
    scanner.running = true;
    currentReader.running = true;
  }

  function apply(path): void {
    if (!path) return;
    error = "";
    current = path;
    applyProc.command = ["sh", script, path];
    applyProc.running = true;
    closeRequested();
  }

  // The wallpaper daemon forgets everything on logout, so replay the saved one.
  Component.onCompleted: restoreProc.running = true

  Process {
    id: restoreProc
    command: ["sh", root.script, "--restore"]
  }

  Process {
    id: applyProc
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.error = text.trim()
    }
  }

  Process {
    id: scanner
    command: ["sh", "-c",
      "find \"$1\" -maxdepth 3 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \\) 2>/dev/null | sort",
      "sh", root.dir]
    stdout: StdioCollector {
      onStreamFinished: root.wallpapers = text.split("\n").filter(l => l !== "")
    }
  }

  Process {
    id: currentReader
    command: ["sh", "-c", "cat \"$HOME/.config/quickshell/wallpaper.conf\" 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: root.current = text.trim()
    }
  }

  PanelWindow {
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-wallpaper-picker"

    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
      Rectangle { anchors.fill: parent; color: root.theme.bgOverlay }
    }

    Rectangle {
      anchors.centerIn: parent
      width: Math.min(820, parent.width - 40)
      height: Math.min(580, parent.height - 40)
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1

      Accessible.role: Accessible.Dialog
      Accessible.name: "Wallpaper picker"

      MouseArea { anchors.fill: parent }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
          Layout.fillWidth: true
          Text {
            text: String.fromCodePoint(0xF0E09) + "  Wallpaper picker"
            color: root.theme.accentPrimary
            font.pixelSize: 14
            font.family: root.font
            font.bold: true
          }
          Item { Layout.fillWidth: true }
          Text {
            text: root.results.length + " images"
            color: root.theme.textMuted
            font.pixelSize: 11
            font.family: root.font
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 36
          radius: 8
          color: root.theme.bgSurface
          border.color: searchInput.activeFocus ? root.theme.accentPrimary : root.theme.bgBorder
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Text {
              text: String.fromCodePoint(0xF0349)
              color: root.theme.textMuted
              font.pixelSize: 13
              font.family: root.font
            }

            TextInput {
              id: searchInput
              Layout.fillWidth: true
              color: root.theme.textPrimary
              font.pixelSize: 13
              font.family: root.font
              clip: true
              onTextChanged: { root.query = text; grid.currentIndex = 0; }
              Accessible.role: Accessible.EditableText
              Accessible.name: "Search wallpapers"

              Keys.onEscapePressed: root.closeRequested()
              Keys.onLeftPressed: grid.moveCurrentIndexLeft()
              Keys.onRightPressed: grid.moveCurrentIndexRight()
              Keys.onUpPressed: grid.moveCurrentIndexUp()
              Keys.onDownPressed: grid.moveCurrentIndexDown()
              Keys.onReturnPressed: root.apply(root.results[grid.currentIndex])
              Keys.onEnterPressed: root.apply(root.results[grid.currentIndex])

              Text {
                anchors.fill: parent
                text: "Search wallpapers..."
                color: root.theme.textMuted
                font: parent.font
                visible: parent.text === ""
              }
            }
          }
        }

        GridView {
          id: grid
          Layout.fillWidth: true
          Layout.fillHeight: true
          cellWidth: Math.floor(width / 3)
          cellHeight: Math.round(cellWidth * 0.62)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: 0
          model: root.results

          delegate: Item {
            id: cell
            required property string modelData
            required property int index
            readonly property bool isCurrent: GridView.isCurrentItem
            readonly property bool isApplied: root.current === modelData

            width: grid.cellWidth
            height: grid.cellHeight

            Accessible.role: Accessible.Button
            Accessible.name: modelData.split("/").pop() + (isApplied ? ", current wallpaper" : "")

            Rectangle {
              anchors.fill: parent
              anchors.margins: 5
              radius: 8
              color: root.theme.bgSurface
              border.color: cell.isCurrent ? root.theme.accentPrimary : (cell.isApplied ? root.theme.accentGreen : "transparent")
              border.width: 2
              clip: true

              Image {
                anchors.fill: parent
                anchors.margins: 2
                source: "file://" + cell.modelData
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 360
                sourceSize.height: 240
                asynchronous: true
                cache: true
              }

              Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 22
                color: Qt.rgba(0, 0, 0, 0.6)
                Text {
                  anchors.centerIn: parent
                  width: parent.width - 8
                  text: cell.modelData.split("/").pop()
                  color: "#ffffff"
                  font.pixelSize: 10
                  font.family: root.font
                  elide: Text.ElideMiddle
                  horizontalAlignment: Text.AlignHCenter
                }
              }

              Rectangle {
                visible: cell.isApplied
                anchors { top: parent.top; right: parent.right; margins: 6 }
                width: 20; height: 20; radius: 10
                color: root.theme.accentGreen
                Text {
                  anchors.centerIn: parent
                  text: String.fromCodePoint(0xF012C)
                  color: root.theme.bgBase
                  font.pixelSize: 12
                  font.family: root.font
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: grid.currentIndex = cell.index
                onClicked: root.apply(cell.modelData)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: grid.count === 0
            text: root.wallpapers.length === 0 ? "No images in ~/Pictures/wallpapers" : "No matches"
            color: root.theme.textMuted
            font.pixelSize: 13
            font.family: root.font
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Text {
            Layout.fillWidth: true
            text: root.error !== "" ? root.error : "enter / click: apply and close    arrows: move    esc: close"
            color: root.error !== "" ? root.theme.accentRed : root.theme.textMuted
            font.pixelSize: 10
            font.family: root.font
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
