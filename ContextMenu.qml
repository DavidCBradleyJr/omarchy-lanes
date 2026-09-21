import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Right-click menu for a taskbar button, built on Omarchy's own PopupCard so
// it matches the stock bar popups (border, fade, click-outside to dismiss).
PopupCard {
  id: menu

  // Set by the taskbar before opening.
  property var toplevel: null
  property var actions: null          // the Taskbar root: exposes the window actions
  property bool edgeTop: false
  property int monitorCount: 1

  readonly property var ipc: toplevel ? toplevel.lastIpcObject : null
  readonly property bool floating: !!(ipc && ipc.floating)
  readonly property bool pinned: !!(ipc && ipc.pinned)
  readonly property bool fullscreen: !!(ipc && ipc.fullscreen)
  readonly property bool minimized: !!(actions && toplevel && actions.isMinimized(toplevel))
  readonly property string currentWorkspace: toplevel && toplevel.workspace ? String(toplevel.workspace.name) : ""

  readonly property int rowHeight: Style.spacing.popupRowHeight
  readonly property int menuWidth: Style.space(230)

  // PopupCard positions itself against a bar; hand it a minimal one.
  bar: QtObject {
    property string position: menu.edgeTop ? "top" : "bottom"
    property var activePopout: null
    function requestPopout(key) { activePopout = key }
    function releasePopout(key) { if (activePopout === key) activePopout = null }
  }

  padding: Style.space(6)
  contentWidth: menuWidth + padding * 2
  contentHeight: column.implicitHeight + padding * 2 + Style.space(4)

  function openFor(item, t) {
    menu.toplevel = t
    menu.anchorItem = item
    Hyprland.refreshToplevels()   // fresh floating/pinned/fullscreen state
    menu.open = true
    menu.anchor.updateAnchor()
  }

  function toggleFor(item, t) {
    if (menu.open) menu.open = false
    else menu.openFor(item, t)
  }

  function run(fn) {
    var t = menu.toplevel
    menu.open = false
    if (t) fn(t)
  }

  // The focus grab routes the keyboard here while the menu is open.
  Item {
    focus: menu.open
    Keys.onEscapePressed: menu.open = false
  }

  Column {
    id: column
    width: menu.menuWidth
    spacing: 0

    // Header: the window's title
    Text {
      width: parent.width
      height: menu.rowHeight
      leftPadding: Style.space(8)
      rightPadding: Style.space(8)
      verticalAlignment: Text.AlignVCenter
      text: menu.toplevel ? (menu.toplevel.title || "") : ""
      elide: Text.ElideRight
      color: Color.popups.text
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }

    MenuRow {
      text: menu.minimized ? "Restore" : "Minimize"
      glyph: menu.minimized ? "󰖯" : "󰖰"
      onTriggered: menu.run(function(t) { menu.minimized ? menu.actions.restore(t) : menu.actions.minimize(t) })
    }
    MenuRow {
      text: "Floating"
      glyph: "󰖲"
      checked: menu.floating
      enabled: !menu.minimized
      onTriggered: menu.run(menu.actions.toggleFloating)
    }
    MenuRow {
      text: "Pin to all workspaces"
      glyph: "󰐃"
      checked: menu.pinned
      enabled: menu.floating && !menu.minimized
      onTriggered: menu.run(menu.actions.togglePin)
    }
    MenuRow {
      text: "Fullscreen"
      glyph: "󰊓"
      checked: menu.fullscreen
      enabled: !menu.minimized
      onTriggered: menu.run(menu.actions.toggleFullscreen)
    }
    MenuRow {
      visible: menu.monitorCount > 1
      text: "Move to next monitor"
      glyph: "󰍺"
      enabled: !menu.minimized
      onTriggered: menu.run(menu.actions.moveToNextMonitor)
    }

    // Move to workspace: 1-9, 0
    Item {
      width: parent.width
      height: menu.rowHeight + Style.space(18)

      Text {
        x: Style.space(8)
        y: Style.space(4)
        text: "Move to workspace"
        color: Color.popups.text
        opacity: 0.55
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }

      Row {
        x: Style.space(6)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(2)
        spacing: Style.space(1)

        Repeater {
          model: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

          Rectangle {
            required property int modelData
            readonly property bool current: menu.currentWorkspace === String(modelData)

            width: Math.floor((menu.menuWidth - Style.space(12) - Style.space(9)) / 10)
            height: Style.space(22)
            radius: Style.cornerRadius
            color: wsMouse.containsMouse ? Style.hoverFill : current ? Style.selectedFill : "transparent"
            border.width: current ? 1 : 0
            border.color: Util.alpha(Color.accent, 0.6)

            Text {
              anchors.centerIn: parent
              text: modelData === 10 ? "0" : String(modelData)
              color: parent.current ? Color.accent : Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              textFormat: Text.PlainText
            }

            MouseArea {
              id: wsMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: menu.run(function(t) { menu.actions.moveToWorkspace(t, String(modelData)) })
            }
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Color.popups.text
      opacity: 0.12
    }

    MenuRow {
      text: "Close window"
      glyph: "󰅖"
      danger: true
      onTriggered: menu.run(menu.actions.close)
    }
  }

  component MenuRow: Item {
    id: row

    property string text: ""
    property string glyph: ""
    property bool checked: false
    property bool danger: false

    signal triggered()

    width: column.width
    height: visible ? menu.rowHeight : 0
    opacity: enabled ? 1 : 0.35

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: rowMouse.containsMouse && row.enabled ? Style.hoverFill : "transparent"
    }

    Text {
      id: glyphText
      x: Style.space(8)
      width: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter
      text: row.glyph
      color: row.danger ? Color.urgent : Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
      textFormat: Text.PlainText
    }

    Text {
      anchors.left: glyphText.right
      anchors.leftMargin: Style.space(6)
      anchors.right: check.left
      anchors.verticalCenter: parent.verticalCenter
      text: row.text
      elide: Text.ElideRight
      color: row.danger ? Color.urgent : Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
    }

    Text {
      id: check
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: row.checked ? "󰄬" : ""
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: row.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: row.triggered()
    }
  }
}
