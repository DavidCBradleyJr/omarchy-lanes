import QtQuick
import qs.Commons
import "ShadeModel.js" as ShadeModel

Item {
  id: root

  property color foreground: Color.popups.text
  property color accent: Color.accent
  property color borderColor: Color.popups.border
  property color surfaceColor: Color.popups.background
  property date now: new Date()
  property int viewYear: now.getFullYear()
  property int viewMonth: now.getMonth()
  readonly property int weekStart: Qt.locale().firstDayOfWeek
  readonly property string todayKey: ShadeModel.dateKey(now.getFullYear(), now.getMonth(), now.getDate())
  readonly property var cells: ShadeModel.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  function step(delta) {
    var next = ShadeModel.stepMonth(viewYear, viewMonth, delta)
    viewYear = next.year
    viewMonth = next.month
  }

  function reset() {
    viewYear = now.getFullYear()
    viewMonth = now.getMonth()
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    Item {
      width: parent.width
      height: Style.space(40)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "CALENDAR // " + Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy").toUpperCase()
        color: root.foreground
        font.family: "monospace"
        font.pixelSize: Style.font.title
        font.bold: true
        textFormat: Text.PlainText
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        NavButton { label: "Today"; wide: true; onPressed: root.reset() }
        NavButton { label: "<"; onPressed: root.step(-1) }
        NavButton { label: ">"; onPressed: root.step(1) }
      }
    }

    Grid {
      id: weekdayGrid
      width: parent.width
      columns: 7
      spacing: Style.space(4)

      Repeater {
        model: 7

        Text {
          required property int index
          width: (weekdayGrid.width - weekdayGrid.spacing * 6) / 7
          height: Style.space(24)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: String(Qt.locale().dayName((root.weekStart + index) % 7, Locale.ShortFormat)).toUpperCase()
          color: root.foreground
          opacity: 0.5
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }
    }

    Grid {
      id: monthGrid
      width: parent.width
      columns: 7
      spacing: Style.space(4)

      Repeater {
        model: root.cells

        Rectangle {
          required property var modelData
          width: (monthGrid.width - monthGrid.spacing * 6) / 7
          height: Math.max(Style.space(40), (root.height - Style.space(84) - monthGrid.spacing * 5) / 6)
          radius: 0
          color: modelData.today ? root.surfaceColor : "transparent"
          border.width: Math.max(1, Style.space(1))
          border.color: modelData.today ? root.accent : root.borderColor

          Text {
            anchors.centerIn: parent
            text: parent.modelData.day
            color: parent.modelData.today ? root.accent : root.foreground
            opacity: parent.modelData.current ? 1 : 0.3
            font.family: "monospace"
            font.pixelSize: Style.font.body
            font.bold: parent.modelData.today
            textFormat: Text.PlainText
          }
        }
      }
    }
  }

  component NavButton: Rectangle {
    id: button
    property string label: ""
    property bool wide: false
    signal pressed()

    width: wide ? Style.space(68) : Style.space(36)
    height: Style.space(32)
    radius: 0
    color: navMouse.containsMouse ? root.surfaceColor : "transparent"
    border.width: Math.max(1, Style.space(1))
    border.color: navMouse.containsMouse ? root.accent : root.borderColor

    Text {
      anchors.centerIn: parent
      text: button.label
      color: root.foreground
      font.family: "monospace"
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }

    MouseArea {
      id: navMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.pressed()
    }
  }
}
