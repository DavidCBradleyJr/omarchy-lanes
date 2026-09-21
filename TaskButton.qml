import QtQuick
import Quickshell
import qs.Commons

// One taskbar button: app icon and optional title.
// Colors and states come from the shared Omarchy Style/Color tokens so the
// button follows whatever theme is active.
Item {
  id: root

  property string iconSource: ""
  property string fallbackGlyph: "?"
  property string label: ""
  property bool active: false
  property bool urgent: false
  property bool minimized: false
  // "working", "waiting" or "" (agent state from the window title)
  property string agent: ""
  property bool showLabel: true
  property bool edgeTop: false
  property real maxWidth: 220
  property int barSize: Style.bar.sizeHorizontal
  property color foreground: Color.bar.text
  property string fontFamily: Style.font.family

  signal clicked(int button)
  signal wheel(int delta)

  readonly property bool hovered: mouse.containsMouse
  readonly property int pad: Style.space(8)
  readonly property int iconSize: Style.bar.iconCanvas
  readonly property color textColor: urgent ? Color.bar.active : foreground

  implicitHeight: barSize
  implicitWidth: showLabel
    ? Math.min(Style.spaceReal(maxWidth), pad * 2 + content.implicitWidth)
    : Math.max(barSize, pad * 2 + iconSize)

  Behavior on implicitWidth {
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: Style.space(2)
    anchors.bottomMargin: Style.space(2)
    radius: Style.cornerRadius
    color: mouse.pressed ? Style.pressedFill
      : root.active ? Style.selectedFill
      : root.hovered ? Style.hoverFill
      : "transparent"

    Behavior on color { ColorAnimation { duration: 120 } }
  }

  // Minimized: a short dash where the underline would be.
  Rectangle {
    visible: root.minimized && !root.active
    width: Style.space(6)
    height: Math.max(2, Style.space(2))
    radius: height / 2
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: root.edgeTop ? parent.top : undefined
    anchors.bottom: root.edgeTop ? undefined : parent.bottom
    color: root.foreground
    opacity: 0.5
  }

  // Active/urgent indicator on the edge facing the screen border.
  Rectangle {
    width: root.active || root.urgent ? parent.width - root.pad * 2 : 0
    height: Math.max(2, Style.space(2))
    radius: height / 2
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: root.edgeTop ? parent.top : undefined
    anchors.bottom: root.edgeTop ? undefined : parent.bottom
    color: root.urgent ? Color.bar.active : Color.accent
    opacity: root.active || root.urgent ? 1 : 0

    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  Row {
    id: content
    anchors.left: parent.left
    anchors.leftMargin: root.pad
    anchors.right: root.showLabel ? parent.right : undefined
    anchors.rightMargin: root.pad
    anchors.horizontalCenter: root.showLabel ? undefined : parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)
    opacity: root.minimized && !root.hovered ? 0.45 : 1

    Behavior on opacity { NumberAnimation { duration: 140 } }


    Item {
      width: root.iconSize
      height: root.iconSize
      anchors.verticalCenter: parent.verticalCenter

      Image {
        id: icon
        anchors.fill: parent
        source: root.iconSource
        sourceSize.width: root.iconSize * 2
        sourceSize.height: root.iconSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        visible: status === Image.Ready
        opacity: root.active || root.hovered ? 1 : 0.8
      }

      // Agent waiting for you: accent dot on the icon's corner. Deliberately
      // static: an infinite animation redraws the whole bar surface every
      // frame, which costs the shell ~20% CPU and makes other popups stutter.
      Rectangle {
        visible: root.agent === "waiting"
        z: 2
        width: Math.max(6, Style.space(7))
        height: width
        radius: width / 2
        x: parent.width - width / 2 - 1
        y: -height / 3
        color: Color.accent
        border.width: 1
        border.color: Color.bar.background

      }

      // Agent working: a small spinner on the icon's corner, stepped slowly
      // (each step repaints the bar).
      Text {
        id: spinner
        property int frame: 0
        visible: root.agent === "working"
        z: 2
        x: parent.width - implicitWidth / 2
        y: parent.height - implicitHeight + Style.space(3)
        text: ["\u25D0", "\u25D3", "\u25D1", "\u25D2"][frame]
        color: Color.accent
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText

        Timer {
          running: root.agent === "working" && root.visible
          repeat: true
          interval: 600
          onTriggered: spinner.frame = (spinner.frame + 1) % 4
        }
      }

      // Monogram when the icon theme has nothing for this app.
      Text {
        anchors.centerIn: parent
        visible: icon.status !== Image.Ready
        text: root.fallbackGlyph
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        textFormat: Text.PlainText
      }
    }

    Text {
      id: title
      visible: root.showLabel && root.label !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, Style.spaceReal(root.maxWidth) - root.pad * 2 - root.iconSize - content.spacing)
      text: root.label
      color: root.textColor
      opacity: root.active ? 1 : 0.65
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
      renderType: Text.NativeRendering

      Behavior on opacity { NumberAnimation { duration: 120 } }
    }
  }


  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(event) { root.clicked(event.button) }
    onWheel: function(event) { root.wheel(event.angleDelta.y) }
  }
}
