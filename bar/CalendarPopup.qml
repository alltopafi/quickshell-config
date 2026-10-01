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

  // Where the clicked bar button sits (window x); the popup hangs under it.
  property real anchorX: 100000

  function close(): void { closeRequested(); }

  readonly property var now: Time.date
  readonly property var monthNames: ["January", "February", "March", "April", "May", "June",
                                     "July", "August", "September", "October", "November", "December"]

  property int viewYear: 2000
  property int viewMonth: 0

  // Easter egg: double-click the progress bar to enter a birth year and the age
  // you expect to reach. Saved outside the (git-tracked) config directory.
  property int birthYear: 0
  property int deathAge: 0
  property bool editing: false
  property bool eggShown: true
  readonly property bool lifeSet: birthYear > 0 && deathAge > 0

  function yearFrac(d) {
    const s = new Date(d.getFullYear(), 0, 1);
    const e = new Date(d.getFullYear() + 1, 0, 1);
    return (d - s) / (e - s);
  }

  readonly property real yearPct: yearFrac(root.now) * 100
  readonly property real lifePct: lifeSet
    ? Math.max(0, Math.min(100, ((root.now.getFullYear() + yearFrac(root.now)) - birthYear) / deathAge * 100))
    : 0

  function dayOfYear(d) {
    return Math.floor((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(d.getFullYear(), 0, 1)) / 86400000) + 1;
  }

  function shiftMonth(delta): void {
    const idx = viewYear * 12 + viewMonth + delta;
    viewYear = Math.floor(idx / 12);
    viewMonth = idx - viewYear * 12;
  }

  function goToday(): void {
    viewYear = root.now.getFullYear();
    viewMonth = root.now.getMonth();
  }

  // 6 weeks x 7 days, Sunday first, including trailing/leading days of neighbours.
  readonly property var cells: {
    const first = new Date(viewYear, viewMonth, 1).getDay();
    const out = [];
    for (let i = 0; i < 42; i++) {
      const d = new Date(viewYear, viewMonth, 1 - first + i);
      out.push({
        day: d.getDate(),
        inMonth: d.getMonth() === viewMonth,
        today: d.getFullYear() === root.now.getFullYear()
            && d.getMonth() === root.now.getMonth()
            && d.getDate() === root.now.getDate()
      });
    }
    return out;
  }

  onOpenChanged: {
    if (open) {
      goToday();
      editing = false;
    }
  }

  readonly property string storePath: Quickshell.env("HOME") + "/.local/state/quickshell-life.json"

  FileView {
    id: store
    path: root.storePath
    printErrors: false
    onLoaded: {
      try {
        const o = JSON.parse(text());
        root.birthYear = o.birthYear | 0;
        root.deathAge = o.deathAge | 0;
        root.eggShown = o.shown !== false;
      } catch (e) {}
    }
  }

  function persist(): void {
    store.setText(JSON.stringify({ birthYear: birthYear, deathAge: deathAge, shown: eggShown }));
  }

  // Double-click on the year bar reveals or hides the whole easter egg.
  function toggleEgg(): void {
    if (eggShown) {
      eggShown = false;
      editing = false;
    } else {
      eggShown = true;
      editing = !lifeSet;
    }
    if (lifeSet) persist();
  }

  function saveLife(): void {
    const by = parseInt(birthField.text);
    const age = parseInt(ageField.text);
    if (!(by >= 1900 && by <= root.now.getFullYear() && age >= 1 && age <= 130)) return;
    birthYear = by;
    deathAge = age;
    editing = false;
    eggShown = true;
    persist();
  }

  component ProgressRow: ColumnLayout {
    id: pr
    property string label
    property real pct
    property color barColor
    property string detail
    signal toggled()

    Layout.fillWidth: true
    spacing: 4

    RowLayout {
      Layout.fillWidth: true

      Text {
        Layout.fillWidth: true
        text: pr.label
        color: root.theme.textSecondary
        font.pixelSize: 11
        font.family: root.font
      }

      Text {
        text: pr.pct.toFixed(1) + "%"
        color: pr.barColor
        font.pixelSize: 12
        font.family: root.font
        font.bold: true
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 8
      radius: 4
      color: root.theme.bgSurface

      Accessible.role: Accessible.ProgressBar
      Accessible.name: pr.label + ": " + pr.pct.toFixed(1) + " percent"

      Rectangle {
        height: parent.height
        radius: 4
        width: parent.width * pr.pct / 100
        color: pr.barColor
        Behavior on width { NumberAnimation { duration: 200 } }
      }

      // Generous hit area so the thin bar is easy to double-click.
      MouseArea {
        anchors.fill: parent
        anchors.topMargin: -8
        anchors.bottomMargin: -8
        onDoubleClicked: pr.toggled()
      }
    }

    Text {
      Layout.fillWidth: true
      text: pr.detail
      color: root.theme.textMuted
      font.pixelSize: 10
      font.family: root.font
    }
  }

  PanelWindow {
    id: popup
    visible: root.open
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-calendar"

    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Clicking the backdrop closes. Transparent so the desktop stays visible.
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Rectangle {
      id: box
      x: Math.max(12, Math.min(parent.width - width - 12, root.anchorX - width / 2))
      y: 44
      width: 304
      height: 24 + layout.implicitHeight
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1
      focus: true

      Accessible.role: Accessible.Dialog
      Accessible.name: "Calendar"

      function dismiss(): void {
        if (root.editing) {
          root.editing = false;
          box.forceActiveFocus();
        } else {
          root.close();
        }
      }

      Keys.onEscapePressed: box.dismiss()

      // Swallow clicks so they don't fall through to the backdrop.
      MouseArea {
        anchors.fill: parent
        onWheel: (wheel) => root.shiftMonth(wheel.angleDelta.y > 0 ? -1 : 1)
      }

      ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Year progress; the life bar (easter egg) is appended below once set.
        // Double-click either bar to open the editor.
        ProgressRow {
          label: root.now.getFullYear() + " progress"
          pct: root.yearPct
          barColor: root.theme.accentPrimary
          onToggled: root.toggleEgg()
          detail: "Day " + root.dayOfYear(root.now) + " of "
                  + Math.round((new Date(root.now.getFullYear() + 1, 0, 1) - new Date(root.now.getFullYear(), 0, 1)) / 86400000)
        }

        ProgressRow {
          visible: root.lifeSet && root.eggShown
          onToggled: root.editing = !root.editing
          label: "Life lived"
          pct: root.lifePct
          barColor: root.theme.accentPrimary
          detail: "Age " + Math.floor(root.now.getFullYear() - root.birthYear) + " of " + root.deathAge
        }

        // Easter-egg editor
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.editing && root.eggShown
          spacing: 6

          onVisibleChanged: {
            if (visible) {
              birthField.text = root.birthYear > 0 ? String(root.birthYear) : "";
              ageField.text = root.deathAge > 0 ? String(root.deathAge) : "";
              birthField.forceActiveFocus();
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 32
              radius: 8
              color: root.theme.bgSurface
              border.width: 1
              border.color: birthField.activeFocus ? root.theme.accentOrange : root.theme.bgBorder

              TextInput {
                id: birthField
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                validator: IntValidator { bottom: 1900; top: 2200 }
                inputMethodHints: Qt.ImhDigitsOnly
                maximumLength: 4
                color: root.theme.textPrimary
                font.pixelSize: 13
                font.family: root.font
                KeyNavigation.tab: ageField
                onAccepted: ageField.forceActiveFocus()
                Keys.onEscapePressed: box.dismiss()

                Text {
                  visible: !parent.text
                  text: "Birth year"
                  color: root.theme.textMuted
                  font: parent.font
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 32
              radius: 8
              color: root.theme.bgSurface
              border.width: 1
              border.color: ageField.activeFocus ? root.theme.accentOrange : root.theme.bgBorder

              TextInput {
                id: ageField
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                validator: IntValidator { bottom: 1; top: 130 }
                inputMethodHints: Qt.ImhDigitsOnly
                maximumLength: 3
                color: root.theme.textPrimary
                font.pixelSize: 13
                font.family: root.font
                KeyNavigation.tab: birthField
                onAccepted: root.saveLife()
                Keys.onEscapePressed: box.dismiss()

                Text {
                  visible: !parent.text
                  text: "Expected age"
                  color: root.theme.textMuted
                  font: parent.font
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          Text {
            text: "Enter to save · Esc to cancel"
            color: root.theme.textMuted
            font.pixelSize: 10
            font.family: root.font
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: root.theme.bgBorder
        }

        // Month / year navigation
        RowLayout {
          Layout.fillWidth: true
          spacing: 2

          Repeater {
            model: [{ t: "«", d: -12, n: "Previous year" }, { t: "‹", d: -1, n: "Previous month" }]

            Rectangle {
              required property var modelData
              Layout.preferredWidth: 28
              Layout.preferredHeight: 28
              radius: 14
              color: navMouse.containsMouse ? root.theme.bgHover : "transparent"
              Accessible.role: Accessible.Button
              Accessible.name: modelData.n

              Text {
                anchors.centerIn: parent
                text: modelData.t
                color: root.theme.textPrimary
                font.pixelSize: 16
                font.family: root.font
              }

              MouseArea {
                id: navMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.shiftMonth(modelData.d)
              }
            }
          }

          // Click the title to jump back to today.
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 14
            color: titleMouse.containsMouse ? root.theme.bgHover : "transparent"
            Accessible.role: Accessible.Button
            Accessible.name: "Go to today"

            Text {
              anchors.centerIn: parent
              text: root.monthNames[root.viewMonth] + " " + root.viewYear
              color: root.theme.accentPrimary
              font.pixelSize: 13
              font.family: root.font
              font.bold: true
            }

            MouseArea {
              id: titleMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToday()
            }
          }

          Repeater {
            model: [{ t: "›", d: 1, n: "Next month" }, { t: "»", d: 12, n: "Next year" }]

            Rectangle {
              required property var modelData
              Layout.preferredWidth: 28
              Layout.preferredHeight: 28
              radius: 14
              color: nav2Mouse.containsMouse ? root.theme.bgHover : "transparent"
              Accessible.role: Accessible.Button
              Accessible.name: modelData.n

              Text {
                anchors.centerIn: parent
                text: modelData.t
                color: root.theme.textPrimary
                font.pixelSize: 16
                font.family: root.font
              }

              MouseArea {
                id: nav2Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.shiftMonth(modelData.d)
              }
            }
          }
        }

        // Weekday header
        RowLayout {
          Layout.fillWidth: true
          spacing: 0

          Repeater {
            model: ["S", "M", "T", "W", "T", "F", "S"]

            Text {
              required property string modelData
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              horizontalAlignment: Text.AlignHCenter
              text: modelData
              color: root.theme.textMuted
              font.pixelSize: 11
              font.family: root.font
            }
          }
        }

        // Day grid
        GridLayout {
          Layout.fillWidth: true
          columns: 7
          rowSpacing: 2
          columnSpacing: 0

          Repeater {
            model: root.cells

            Item {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.preferredHeight: 32

              Rectangle {
                anchors.centerIn: parent
                width: 30
                height: 30
                radius: 15
                color: modelData.today ? root.theme.accentPrimary : "transparent"
              }

              Text {
                anchors.centerIn: parent
                text: modelData.day
                color: modelData.today ? root.theme.bgBase
                     : modelData.inMonth ? root.theme.textPrimary
                     : root.theme.textMuted
                opacity: modelData.inMonth || modelData.today ? 1 : 0.5
                font.pixelSize: 12
                font.family: root.font
                font.bold: modelData.today
              }
            }
          }
        }
      }
    }
  }
}
