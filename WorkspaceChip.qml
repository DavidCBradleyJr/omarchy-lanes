import QtQuick
import qs.Commons

// Workspace label in front of a group of windows. Click to go there.
Item {
  id: root

  property string label: ""
  property bool current: false
  property int barSize: Style.bar.sizeHorizontal
  property string fontFamily: Style.font.family

  signal clicked()

  implicitWidth: Math.max(Style.space(18), text.implicitWidth + Style.space(10))
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: Style.space(5)
    anchors.bottomMargin: Style.space(5)
    radius: Style.cornerRadius
    color: mouse.containsMouse ? Style.hoverFill : Style.normalFill
    border.width: Style.normalBorderWidth
    border.color: root.current ? Util.alpha(Color.accent, 0.6) : Style.normalBorderColor

    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Text {
    id: text
    anchors.centerIn: parent
    text: root.label
    color: root.current ? Color.accent : Color.bar.text
    opacity: root.current ? 1 : 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: root.current
    textFormat: Text.PlainText
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
