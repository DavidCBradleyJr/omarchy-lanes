import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import "ShadeModel.js" as ShadeModel

Item {
  id: root

  property color foreground: Color.popups.text
  property color accent: Color.accent
  property color borderColor: Color.popups.border
  property color surfaceColor: Color.popups.background
  property string preferredKey: ""
  property int positionTick: 0
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayer: selectPlayer()
  readonly property real currentPosition: {
    root.positionTick
    return activePlayer && activePlayer.positionSupported ? Math.max(0, activePlayer.position) : 0
  }

  function playerKey(player) {
    return player ? String(player.dbusName || player.identity || player.desktopEntry || player.uniqueId || "") : ""
  }

  function selectPlayer() {
    var fallback = null
    for (var i = 0; i < players.length; i++) {
      var player = players[i]
      if (playerKey(player) === preferredKey) return player
      if (!fallback && player.isPlaying) fallback = player
    }
    if (fallback) return fallback
    for (var j = 0; j < players.length; j++)
      if (players[j].trackTitle || players[j].trackArtist) return players[j]
    return players.length > 0 ? players[0] : null
  }

  function playPause() {
    var player = activePlayer
    if (!player) return
    if (player.isPlaying && player.canPause) player.pause()
    else if (!player.isPlaying && player.canPlay) player.play()
    else if (player.canTogglePlaying) player.togglePlaying()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.activePlayer !== null
    onTriggered: root.positionTick++
  }

  Item {
    anchors.fill: parent

    Row {
      id: playerRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: sourceRow.top
      anchors.bottomMargin: Style.space(12)
      spacing: Style.space(28)

      Rectangle {
        id: artwork
        width: Math.min(height, Style.space(260))
        height: parent.height
        radius: 0
        color: root.surfaceColor
        border.width: Math.max(1, Style.space(1))
        border.color: root.borderColor
        clip: true

        Image {
          anchors.fill: parent
          source: root.activePlayer ? root.activePlayer.trackArtUrl : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          visible: status === Image.Ready
        }

        Text {
          anchors.centerIn: parent
          visible: !root.activePlayer || !root.activePlayer.trackArtUrl
          text: "󰝚"
          color: root.foreground
          opacity: 0.35
          font.family: "monospace"
          font.pixelSize: Math.max(Style.font.displayLarge, Style.space(54))
          textFormat: Text.PlainText
        }
      }

      Column {
        width: parent.width - artwork.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(9)

        Text {
          width: parent.width
          text: root.activePlayer ? (root.activePlayer.trackTitle || "Nothing playing") : "No media player"
          color: root.foreground
          font.family: "monospace"
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          width: parent.width
          text: root.activePlayer ? (root.activePlayer.trackArtist || root.activePlayer.identity || "").toUpperCase() : "START SPOTIFY OR ANOTHER MPRIS PLAYER"
          color: root.foreground
          opacity: 0.65
          font.family: "monospace"
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          width: parent.width
          visible: text !== ""
          text: root.activePlayer ? (root.activePlayer.trackAlbum || "") : ""
          color: root.foreground
          opacity: 0.42
          font.family: "monospace"
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Item {
          width: parent.width
          height: Style.space(32)
          visible: root.activePlayer && root.activePlayer.lengthSupported && root.activePlayer.length > 0

          Rectangle {
            id: progressTrack
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(4)
            radius: height / 2
            color: root.foreground
            opacity: 0.18
          }

          Rectangle {
            anchors.left: progressTrack.left
            anchors.verticalCenter: progressTrack.verticalCenter
            width: progressTrack.width * ShadeModel.clamp(root.currentPosition / Math.max(1, root.activePlayer ? root.activePlayer.length : 1), 0, 1)
            height: Style.space(4)
            radius: height / 2
            color: root.accent
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: root.activePlayer && root.activePlayer.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: function(mouse) {
              if (root.activePlayer && root.activePlayer.canSeek && root.activePlayer.length > 0)
                root.activePlayer.position = ShadeModel.clamp(mouse.x / width, 0, 1) * root.activePlayer.length
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: (parent.width - Style.space(8)) / 2
            text: ShadeModel.formatDuration(root.currentPosition)
            color: root.foreground
            opacity: 0.45
            font.family: "monospace"
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
          Text {
            width: (parent.width - Style.space(8)) / 2
            horizontalAlignment: Text.AlignRight
            text: ShadeModel.formatDuration(root.activePlayer && root.activePlayer.lengthSupported ? root.activePlayer.length : 0)
            color: root.foreground
            opacity: 0.45
            font.family: "monospace"
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          MediaButton {
            glyph: "󰒮"
            enabled: root.activePlayer && root.activePlayer.canGoPrevious
            onPressed: root.activePlayer.previous()
          }
          MediaButton {
            glyph: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
            prominent: true
            enabled: root.activePlayer && (root.activePlayer.canPlay || root.activePlayer.canPause || root.activePlayer.canTogglePlaying)
            onPressed: root.playPause()
          }
          MediaButton {
            glyph: "󰒭"
            enabled: root.activePlayer && root.activePlayer.canGoNext
            onPressed: root.activePlayer.next()
          }
        }
      }
    }

    Row {
      id: sourceRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: root.players.length > 1 ? Style.space(38) : 0
      spacing: Style.space(6)
      visible: root.players.length > 1

      Repeater {
        model: root.players

        Rectangle {
          id: sourceButton
          required property var modelData
          readonly property bool selected: root.activePlayer === modelData
          width: Math.min(Style.space(180), sourceLabel.implicitWidth + Style.space(24))
          height: sourceRow.height
          radius: 0
          color: selected ? root.surfaceColor : "transparent"
          border.width: Math.max(1, Style.space(1))
          border.color: selected ? root.accent : root.borderColor

          Text {
            id: sourceLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, Style.space(156))
            text: sourceButton.modelData.identity || sourceButton.modelData.desktopEntry || "Media"
            color: sourceButton.selected ? root.accent : root.foreground
            font.family: "monospace"
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }

          MouseArea {
            id: sourceMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.preferredKey = root.playerKey(sourceButton.modelData)
          }
        }
      }
    }
  }

  component MediaButton: Rectangle {
    id: button
    property string glyph: ""
    property bool prominent: false
    signal pressed()

    width: prominent ? Style.space(52) : Style.space(42)
    height: width
    radius: width / 2
    color: prominent ? root.surfaceColor : (controlMouse.containsMouse ? root.surfaceColor : "transparent")
    border.width: Math.max(1, Style.space(1))
    border.color: prominent ? root.accent : root.borderColor
    opacity: enabled ? 1 : 0.3

    Text {
      anchors.centerIn: parent
      text: button.glyph
      color: button.prominent ? root.accent : root.foreground
      font.family: "monospace"
      font.pixelSize: button.prominent ? Style.font.iconLarge : Style.font.icon
      textFormat: Text.PlainText
    }

    MouseArea {
      id: controlMouse
      anchors.fill: parent
      enabled: button.enabled
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: button.pressed()
    }
  }
}
