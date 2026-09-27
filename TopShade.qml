import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "TaskbarModel.js" as Model

PanelWindow {
  id: root

  property var settings: null
  property var hyprMonitor: null
  property bool hoverOpen: false
  property bool heldOpen: false
  property int selectedTab: 0
  property int displayedTab: 0
  property int transitionDirection: 1
  property date now: shadeClock.date
  readonly property color shadeBackground: "#10111a"
  readonly property color shadeSurface: "#171925"
  readonly property color shadeBorder: "#30334b"
  readonly property color shadeText: "#c7c9de"
  readonly property color shadeMuted: "#747891"
  readonly property color shadeAccent: "#858cff"
  readonly property color shadeCyan: "#55d6d2"
  readonly property color shadeAmber: "#d9b85f"
  readonly property bool opened: hoverOpen || heldOpen
  readonly property int peek: Math.max(3, Style.space(3))
  readonly property int desiredHeight: settings ? Style.space(settings.shadeHeight) : Style.space(480)
  property real reveal: opened ? 1 : 0
  readonly property var tabs: [
    { label: "01  CALENDAR", component: calendarComponent },
    { label: "02  CLOCK", component: clockComponent },
    { label: "03  MUSIC", component: mediaComponent },
    { label: "04  WEATHER", component: weatherComponent }
  ]

  function showShade(tab) {
    if (tab !== undefined && Number(tab) >= 0 && Number(tab) < tabs.length) selectedTab = Number(tab)
    heldOpen = true
    hoverOpen = true
  }

  function closeShade() {
    heldOpen = false
    hoverOpen = false
  }

  function toggleShade() {
    if (opened && heldOpen) closeShade()
    else showShade(selectedTab)
    return opened ? "open" : "closed"
  }

  function transitionToTab(index) {
    if (index === displayedTab) {
      tabTransition.stop()
      scanTransition.stop()
      pageLoader.x = 0
      pageLoader.opacity = 1
      transitionScan.opacity = 0
      return
    }

    transitionDirection = index > displayedTab ? 1 : -1
    if (!opened) {
      displayedTab = index
      pageLoader.x = 0
      pageLoader.opacity = 1
      return
    }

    tabTransition.restart()
    scanTransition.restart()
  }

  onSelectedTabChanged: transitionToTab(selectedTab)

  Component.onCompleted: Model.registerShade(root)
  Component.onDestruction: Model.unregisterShade(root)

  anchors {
    top: true
    left: true
    right: true
  }
  implicitHeight: Math.min(screen ? screen.height - Style.space(40) : desiredHeight, desiredHeight)
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  surfaceFormat.opaque: false

  WlrLayershell.namespace: "omarchy-lanes-shade"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // Keep the layer surface stationary. Moving the surface itself makes
  // compositors drop hover while it slides. The input mask grows with the
  // animated body, so closed shades only intercept the top-edge trigger.
  mask: Region { item: interactionRegion }

  Item {
    id: interactionRegion
    width: root.width
    height: root.peek + Math.round((root.height - root.peek) * root.reveal)
  }

  SystemClock {
    id: shadeClock
    precision: SystemClock.Minutes
  }

  Behavior on reveal {
    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
  }

  HoverHandler {
    onHoveredChanged: {
      if (hovered) {
        closeDelay.stop()
        if (!root.opened) openDelay.restart()
        else root.hoverOpen = true
      } else {
        openDelay.stop()
        if (!root.heldOpen) closeDelay.restart()
      }
    }
  }

  Timer {
    id: openDelay
    interval: 170
    onTriggered: root.hoverOpen = true
  }

  Timer {
    id: closeDelay
    interval: 650
    onTriggered: root.hoverOpen = false
  }

  Rectangle {
    id: shadeBody
    x: 0
    y: -Math.round((height - root.peek) * (1 - root.reveal))
    width: parent.width
    height: parent.height
    color: root.shadeBackground
    border.width: Math.max(1, Style.space(1))
    border.color: root.shadeBorder

    Item {
      id: technicalGrid
      anchors.fill: parent
      anchors.margins: Style.space(10)
      opacity: 0.22

      Repeater {
        model: 17
        Rectangle {
          required property int index
          x: Math.round(index * technicalGrid.width / 16)
          width: Math.max(1, Style.space(1))
          height: technicalGrid.height
          color: root.shadeBorder
        }
      }

      Repeater {
        model: 7
        Rectangle {
          required property int index
          y: Math.round(index * technicalGrid.height / 6)
          width: technicalGrid.width
          height: Math.max(1, Style.space(1))
          color: root.shadeBorder
        }
      }
    }

    Column {
      anchors.fill: parent

      Item {
        id: header
        width: parent.width
        height: Style.space(62)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(22)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            height: width
            color: "transparent"
            border.width: Math.max(1, Style.space(1))
            border.color: root.shadeAccent

            Rectangle {
              anchors.centerIn: parent
              width: Style.space(5)
              height: width
              color: root.shadeAccent
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "LANES // CONTROL"
            color: root.shadeText
            font.family: "monospace"
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            textFormat: Text.PlainText
          }
        }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(2)

          Repeater {
            model: root.tabs

            Rectangle {
              id: tabButton
              required property var modelData
              required property int index
              width: Style.space(132)
              height: Style.space(38)
              radius: 0
              color: root.selectedTab === index ? root.shadeSurface : (tabMouse.containsMouse ? "#1c1e2d" : "transparent")
              border.width: Math.max(1, Style.space(1))
              border.color: root.selectedTab === index ? root.shadeAccent : root.shadeBorder

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                height: Math.max(1, Style.space(2))
                color: root.shadeCyan
                opacity: root.selectedTab === tabButton.index ? 1 : 0

                Behavior on opacity {
                  NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
              }

              Text {
                anchors.centerIn: parent
                text: tabButton.modelData.label
                color: root.selectedTab === tabButton.index ? root.shadeAmber : root.shadeMuted
                font.family: "monospace"
                font.pixelSize: Style.font.caption
                font.bold: root.selectedTab === tabButton.index
                textFormat: Text.PlainText
              }

              MouseArea {
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedTab = tabButton.index
              }
            }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(22)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(7)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(5)
            height: width
            radius: width / 2
            color: root.shadeCyan
          }

          Text {
            text: "LIVE // " + Qt.formatTime(root.now, "HH:mm")
            color: root.shadeCyan
            font.family: "monospace"
            font.pixelSize: Style.font.caption
            font.bold: true
            textFormat: Text.PlainText
          }
        }
      }

      Rectangle {
        width: parent.width
        height: Math.max(1, Style.space(1))
        color: root.shadeBorder
      }

      Item {
        id: contentArea
        width: parent.width
        height: parent.height - header.height - handle.height - Style.space(1)

        Item {
          id: pageViewport
          anchors.fill: parent
          anchors.leftMargin: Math.max(Style.space(22), Math.round((parent.width - Style.space(1240)) / 2))
          anchors.rightMargin: anchors.leftMargin
          anchors.topMargin: Style.space(18)
          anchors.bottomMargin: Style.space(12)
          clip: true

          Loader {
            id: pageLoader
            x: 0
            y: 0
            width: parent.width
            height: parent.height
            sourceComponent: root.tabs[root.displayedTab].component
          }

          Rectangle {
            id: transitionScan
            z: 10
            x: -width
            y: 0
            width: Style.space(18)
            height: parent.height
            color: root.transitionDirection > 0 ? root.shadeCyan : root.shadeAmber
            opacity: 0

            Rectangle {
              x: root.transitionDirection > 0 ? parent.width - width : 0
              width: Math.max(1, Style.space(2))
              height: parent.height
              color: root.shadeText
            }
          }
        }
      }

      Item {
        id: handle
        width: parent.width
        height: Style.space(30)

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(56)
          height: Style.space(4)
          radius: 0
          color: handleMouse.containsMouse ? root.shadeCyan : root.shadeAccent
          opacity: handleMouse.containsMouse ? 0.9 : 0.48
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(22)
          anchors.verticalCenter: parent.verticalCenter
          text: Qt.formatDateTime(root.now, "ddd dd MMM yyyy").toUpperCase()
          color: root.shadeMuted
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(22)
          anchors.verticalCenter: parent.verticalCenter
          text: "MONITOR // " + (root.hyprMonitor ? String(root.hyprMonitor.name) : "ACTIVE")
          color: root.shadeMuted
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }

        MouseArea {
          id: handleMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.closeShade()
        }
      }
    }
  }

  SequentialAnimation {
    id: tabTransition

    ParallelAnimation {
      NumberAnimation {
        target: pageLoader
        property: "x"
        to: -root.transitionDirection * Style.space(34)
        duration: 105
        easing.type: Easing.InCubic
      }
      NumberAnimation {
        target: pageLoader
        property: "opacity"
        to: 0
        duration: 90
        easing.type: Easing.InQuad
      }
    }

    ScriptAction {
      script: {
        root.displayedTab = root.selectedTab
        pageLoader.x = root.transitionDirection * Style.space(48)
      }
    }

    PauseAnimation { duration: 24 }

    ParallelAnimation {
      NumberAnimation {
        target: pageLoader
        property: "x"
        to: 0
        duration: 210
        easing.type: Easing.OutExpo
      }
      NumberAnimation {
        target: pageLoader
        property: "opacity"
        to: 1
        duration: 165
        easing.type: Easing.OutCubic
      }
    }
  }

  ParallelAnimation {
    id: scanTransition

    NumberAnimation {
      target: transitionScan
      property: "x"
      from: root.transitionDirection > 0 ? -transitionScan.width : pageViewport.width
      to: root.transitionDirection > 0 ? pageViewport.width : -transitionScan.width
      duration: 340
      easing.type: Easing.OutCubic
    }

    SequentialAnimation {
      NumberAnimation { target: transitionScan; property: "opacity"; to: 0.22; duration: 55 }
      PauseAnimation { duration: 210 }
      NumberAnimation { target: transitionScan; property: "opacity"; to: 0; duration: 75 }
    }
  }

  Component {
    id: calendarComponent
    ShadeCalendar { foreground: root.shadeText; accent: root.shadeAmber; borderColor: root.shadeBorder; surfaceColor: root.shadeSurface }
  }

  Component {
    id: clockComponent
    ShadeClock { foreground: root.shadeText; accent: root.shadeCyan; borderColor: root.shadeBorder }
  }

  Component {
    id: mediaComponent
    ShadeMedia { foreground: root.shadeText; accent: root.shadeAccent; borderColor: root.shadeBorder; surfaceColor: root.shadeSurface }
  }

  Component {
    id: weatherComponent
    ShadeWeather { foreground: root.shadeText; accent: root.shadeCyan; borderColor: root.shadeBorder; surfaceColor: root.shadeSurface }
  }
}
