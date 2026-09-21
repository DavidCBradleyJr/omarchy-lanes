import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "TaskbarModel.js" as Model

// Lanes in the Omarchy top bar.
//   mode "summary": agents waiting / working (always shown, 0 when idle) and
//                   minimized windows (only when there are some) as small
//                   counters; click for a popup that jumps to any of them.
//   mode "lanes":   the whole lanes strip inline in the bar.
BarWidget {
  id: root
  moduleName: "davidcbradleyjr.lanes"

  readonly property string mode: core.settings.mode
  readonly property var screenMonitor: {
    var w = root.QsWindow.window
    return w && w.screen ? Hyprland.monitorFor(w.screen) : null
  }

  readonly property int waiting: core.agentTotals.waiting
  readonly property int working: core.agentTotals.working
  readonly property int minimizedCount: {
    var n = 0
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) if (core.isMinimized(all[i])) n++
    return n
  }
  visible: mode === "lanes" ? !vertical : true
  implicitWidth: !visible ? 0 : (mode === "lanes" ? lanes.implicitWidth : summary.implicitWidth)
  implicitHeight: barSize

  Actions {
    id: core
    shell: root.bar ? root.bar.shell : null
  }

  // ------------------------------------------------------------- lanes mode
  // The Omarchy bar doesn't negotiate space between sections, so the inline
  // strip measures its own budget: from its edge to the bar's center, minus
  // room reserved for the center section (clock, indicators).
  property real budget: Infinity

  function recomputeBudget() {
    var w = root.QsWindow.window
    if (!w || root.mode !== "lanes") { root.budget = Infinity; return }
    var half = w.width / 2
    var reserve = Style.space(core.settings.centerReserve)
    var p = root.mapToItem(null, 0, 0)
    var leftSide = p.x + root.width / 2 < half
    var avail = leftSide ? half - reserve - p.x : p.x + root.width - (half + reserve)
    root.budget = Math.max(Style.space(60), Math.floor(avail))
  }

  onWidthChanged: budgetTimer.restart()
  onModeChanged: budgetTimer.restart()
  Timer { id: budgetTimer; interval: 100; onTriggered: root.recomputeBudget() }
  // Neighbouring widgets can grow or shrink without telling us.
  Timer { interval: 2000; repeat: true; running: root.mode === "lanes"; onTriggered: root.recomputeBudget() }

  LaneStrip {
    id: lanes
    visible: root.mode === "lanes"
    actions: core
    maxWidth: root.budget
    hyprMonitor: root.screenMonitor
    barSize: root.barSize
    edgeTop: !root.bar || root.bar.position !== "bottom"
    anchors.verticalCenter: parent.verticalCenter
  }

  // ------------------------------------------------------------- summary mode
  Row {
    id: summary
    visible: root.mode === "summary"
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Counter {
      glyph: "✳"
      count: root.waiting
      filter: "waiting"
      showZero: true
      accent: true
      tooltip: root.waiting === 1 ? "1 agent waiting for you" : root.waiting + " agents waiting for you"
    }
    Counter {
      glyph: "◐"
      count: root.working
      filter: "working"
      showZero: true
      tooltip: root.working === 1 ? "1 agent working" : root.working + " agents working"
    }
    Counter {
      glyph: "󰖰"   // nf-md-window_minimize
      count: root.minimizedCount
      filter: "minimized"
      tooltip: root.minimizedCount === 1 ? "1 minimized window" : root.minimizedCount + " minimized windows"
    }
  }

  component Counter: Item {
    id: counter
    property string glyph: ""
    property int count: 0
    property bool accent: false
    property bool showZero: false
    property string filter: ""
    property string tooltip: ""

    visible: count > 0 || showZero
    implicitWidth: visible ? label.implicitWidth + Style.space(12) : 0
    implicitHeight: root.barSize

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: Style.space(4)
      anchors.bottomMargin: Style.space(4)
      radius: Style.cornerRadius
      color: counterMouse.containsMouse || (popup.open && popup.filter === counter.filter) ? Style.hoverFill : "transparent"
    }

    Text {
      id: label
      anchors.centerIn: parent
      text: counter.glyph + " " + counter.count
      color: counter.accent && counter.count > 0 ? Color.accent : (root.bar ? root.bar.barForeground : Color.bar.text)
      opacity: counter.count > 0 ? 1 : 0.45
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
    }

    MouseArea {
      id: counterMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar && !popup.open) root.bar.showTooltip(counter, counter.tooltip)
      onExited: if (root.bar) root.bar.hideTooltip(counter)
      onClicked: {
        if (root.bar) root.bar.hideTooltip(counter)
        popup.anchorItem = counter
        if (popup.open && popup.filter === counter.filter) {
          popup.open = false
        } else {
          popup.filter = counter.filter
          popup.open = true
          popup.anchor.updateAnchor()
        }
      }
    }
  }

  // ------------------------------------------------------------- popup
  // One list per counter: agents waiting, agents working (model, task, what
  // it's doing now), or minimized windows. Click a row to go there.
  PopupCard {
    id: popup
    property string filter: "working"

    anchorItem: summary
    bar: root.bar
    contentWidth: Style.space(380)
    contentHeight: fittedContentHeight(list.implicitHeight, Style.space(520))

    readonly property var agentRows: popup.open && popup.filter !== "minimized" ? core.agentItemsIn(popup.filter) : []
    readonly property var minimizedRows: {
      if (!popup.open || popup.filter !== "minimized") return []
      var all = Hyprland.toplevels.values
      return all.filter(function(t) { return core.isMinimized(t) })
    }
    readonly property int rowCount: popup.filter === "minimized" ? minimizedRows.length : agentRows.length
    readonly property string heading: popup.filter === "waiting" ? "Waiting for you"
      : popup.filter === "working" ? "Working" : "Minimized"

    Column {
      id: list
      width: parent.width
      spacing: Style.space(2)

      Text {
        width: parent.width
        height: Style.spacing.popupRowHeight
        verticalAlignment: Text.AlignVCenter
        leftPadding: Style.space(6)
        text: popup.heading + "  \u00B7  " + popup.rowCount
        color: Color.popups.text
        opacity: 0.55
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }

      Text {
        visible: popup.rowCount === 0
        width: parent.width
        leftPadding: Style.space(6)
        bottomPadding: Style.space(6)
        text: popup.filter === "minimized" ? "Nothing minimized" : "No agents " + (popup.filter === "waiting" ? "waiting" : "working") + " right now"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }

      // Agents
      Repeater {
        model: popup.agentRows

        Item {
          id: agentRow
          required property var modelData
          readonly property var toplevel: core.toplevelFor(modelData.address)

          width: list.width
          height: rowColumn.implicitHeight + Style.space(10)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: agentMouse.containsMouse ? Style.hoverFill : "transparent"
          }

          Image {
            id: agentIcon
            x: Style.space(8)
            y: Style.space(7)
            width: Style.bar.iconCanvas
            height: width
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            source: agentRow.toplevel ? core.iconForApp(core.appIdOf(agentRow.toplevel)) : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }

          Column {
            id: rowColumn
            anchors.left: agentIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            y: Style.space(5)
            spacing: Style.space(2)

            // Task title, with the state glyph
            Text {
              width: parent.width
              text: (agentRow.modelData.state === "waiting" ? "\u2733  " : "\u25D0  ") + agentRow.modelData.title
              elide: Text.ElideRight
              color: agentRow.modelData.state === "waiting" ? Color.accent : Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              textFormat: Text.PlainText
            }

            // App and model
            Row {
              spacing: Style.space(6)

              Text {
                text: agentRow.modelData.app
                color: Color.popups.text
                opacity: 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                textFormat: Text.PlainText
              }

              Rectangle {
                visible: agentRow.modelData.model !== ""
                width: modelText.implicitWidth + Style.space(10)
                height: modelText.implicitHeight + Style.space(2)
                radius: Style.cornerRadius
                color: Style.selectedFill
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: modelText
                  anchors.centerIn: parent
                  text: agentRow.modelData.model
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                }
              }
            }

            // What it's doing now
            Text {
              visible: agentRow.modelData.activity !== ""
              width: parent.width
              text: agentRow.modelData.activity
              elide: Text.ElideRight
              maximumLineCount: 2
              wrapMode: Text.Wrap
              color: Color.popups.text
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
          }

          MouseArea {
            id: agentMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              popup.open = false
              core.openAgent(agentRow.modelData)
            }
          }
        }
      }

      // Minimized windows
      Repeater {
        model: popup.minimizedRows

        Item {
          id: minRow
          required property var modelData
          readonly property string appId: core.appIdOf(modelData)

          width: list.width
          height: Style.spacing.popupRowHeight

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: minMouse.containsMouse ? Style.hoverFill : "transparent"
          }

          Image {
            id: minIcon
            x: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.bar.iconCanvas
            height: width
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            source: core.iconForApp(minRow.appId)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }

          Text {
            anchors.left: minIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: Model.agentLabel(minRow.modelData.title || minRow.appId)
            elide: Text.ElideRight
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }

          MouseArea {
            id: minMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              popup.open = false
              core.restore(minRow.modelData)
            }
          }
        }
      }
    }
  }

  // Keyboard / script access: omarchy-shell shell call davidcbradleyjr.lanes agents working
  Component.onCompleted: Model.registerWidget(root)
  Component.onDestruction: Model.unregisterWidget(root)

  function showList(filter) {
    popup.filter = filter || "working"
    popup.anchorItem = summary
    popup.open = !popup.open
    popup.anchor.updateAnchor()
    return popup.open
  }
}
