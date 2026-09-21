import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "TaskbarModel.js" as Model

// Lanes in the Omarchy top bar.
//   mode "summary": agents waiting / working and minimized windows as small
//                   counters; click for a popup that jumps to any of them.
//                   Hides itself when there's nothing to show.
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
  readonly property bool hasSummary: waiting + working + minimizedCount > 0

  visible: mode === "lanes" ? !vertical : hasSummary
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
      accent: true
      tooltip: root.waiting === 1 ? "1 agent waiting for you" : root.waiting + " agents waiting for you"
    }
    Counter {
      glyph: "◐"
      count: root.working
      tooltip: root.working === 1 ? "1 agent working" : root.working + " agents working"
    }
    Counter {
      glyph: "󰖰"   // nf-md-window_minimize
      count: root.minimizedCount
      tooltip: root.minimizedCount === 1 ? "1 minimized window" : root.minimizedCount + " minimized windows"
    }
  }

  component Counter: Item {
    id: counter
    property string glyph: ""
    property int count: 0
    property bool accent: false
    property string tooltip: ""

    visible: count > 0
    implicitWidth: visible ? label.implicitWidth + Style.space(12) : 0
    implicitHeight: root.barSize

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: Style.space(4)
      anchors.bottomMargin: Style.space(4)
      radius: Style.cornerRadius
      color: counterMouse.containsMouse || popup.open ? Style.hoverFill : "transparent"
    }

    Text {
      id: label
      anchors.centerIn: parent
      text: counter.glyph + " " + counter.count
      color: counter.accent ? Color.accent : (root.bar ? root.bar.barForeground : Color.bar.text)
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
        popup.anchorItem = summary
        popup.open = !popup.open
      }
    }
  }

  // ------------------------------------------------------------- popup
  PopupCard {
    id: popup
    anchorItem: summary
    bar: root.bar
    contentWidth: Style.space(320)
    contentHeight: fittedContentHeight(list.implicitHeight, Style.space(460))

    // Agents first (waiting before working), then minimized windows, each in
    // workspace order.
    readonly property var rows: {
      if (!popup.open) return []
      var windows = core.allWindows()
      var waiting = [], working = [], minimized = []
      for (var i = 0; i < windows.length; i++) {
        var t = windows[i].toplevel
        var state = core.agentStates[core.addressOf(t)] || ""
        var row = { toplevel: t, state: state, label: windows[i].groupLabel }
        if (state === "waiting") waiting.push(row)
        else if (state === "working") working.push(row)
        else if (core.isMinimized(t)) minimized.push(row)
      }
      return waiting.concat(working).concat(minimized)
    }

    Column {
      id: list
      width: parent.width
      spacing: 0

      Text {
        visible: popup.rows.length === 0
        width: parent.width
        height: Style.spacing.popupRowHeight
        verticalAlignment: Text.AlignVCenter
        text: "No agents or minimized windows"
        color: Color.popups.text
        opacity: 0.55
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: popup.rows

        Item {
          id: rowItem
          required property var modelData
          readonly property var toplevel: modelData.toplevel
          readonly property string appId: core.appIdOf(toplevel)

          width: list.width
          height: Style.spacing.popupRowHeight

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: rowMouse.containsMouse ? Style.hoverFill : "transparent"
          }

          Text {
            id: stateGlyph
            x: Style.space(6)
            width: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            text: rowItem.modelData.state === "waiting" ? "✳"
              : rowItem.modelData.state === "working" ? "◐" : "󰖰"
            color: rowItem.modelData.state === "waiting" ? Color.accent : Color.popups.text
            opacity: rowItem.modelData.state === "" ? 0.55 : 1
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }

          Image {
            id: rowIcon
            anchors.left: stateGlyph.right
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.bar.iconCanvas
            height: width
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            source: core.iconForApp(rowItem.appId)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }

          Text {
            anchors.left: rowIcon.right
            anchors.leftMargin: Style.space(8)
            anchors.right: wsLabel.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: Model.agentLabel(rowItem.toplevel.title || rowItem.appId)
            elide: Text.ElideRight
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }

          Text {
            id: wsLabel
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: rowItem.modelData.label
            color: Color.popups.text
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              popup.open = false
              core.activate(rowItem.toplevel)
            }
          }
        }
      }
    }
  }
}
