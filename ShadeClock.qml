import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root

  property color foreground: Color.popups.text
  property color accent: Color.accent
  property color borderColor: Color.popups.border
  property date now: clock.date

  SystemClock {
    id: clock
    precision: SystemClock.Seconds
    onDateChanged: face.requestPaint()
  }

  Row {
    anchors.centerIn: parent
    spacing: Style.space(42)

    Canvas {
      id: face
      width: Math.min(root.height - Style.space(30), Style.space(250))
      height: width

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var cx = width / 2
        var cy = height / 2
        var radius = Math.min(width, height) / 2 - 3

        ctx.strokeStyle = root.foreground
        ctx.globalAlpha = 0.22
        ctx.lineWidth = Math.max(1, Style.space(1))
        ctx.beginPath()
        ctx.arc(cx, cy, radius, 0, Math.PI * 2)
        ctx.stroke()

        for (var i = 0; i < 12; i++) {
          var angle = i * Math.PI / 6 - Math.PI / 2
          var inner = radius - (i % 3 === 0 ? 13 : 7)
          ctx.globalAlpha = i % 3 === 0 ? 0.75 : 0.3
          ctx.lineWidth = i % 3 === 0 ? 2 : 1
          ctx.beginPath()
          ctx.moveTo(cx + Math.cos(angle) * inner, cy + Math.sin(angle) * inner)
          ctx.lineTo(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius)
          ctx.stroke()
        }

        var hours = root.now.getHours() % 12 + root.now.getMinutes() / 60
        var minutes = root.now.getMinutes() + root.now.getSeconds() / 60
        var seconds = root.now.getSeconds()

        function hand(angle, length, lineWidth, color, alpha) {
          ctx.strokeStyle = color
          ctx.globalAlpha = alpha
          ctx.lineCap = "round"
          ctx.lineWidth = lineWidth
          ctx.beginPath()
          ctx.moveTo(cx, cy)
          ctx.lineTo(cx + Math.cos(angle) * length, cy + Math.sin(angle) * length)
          ctx.stroke()
        }

        hand(hours * Math.PI / 6 - Math.PI / 2, radius * 0.52, 6, root.foreground, 0.95)
        hand(minutes * Math.PI / 30 - Math.PI / 2, radius * 0.74, 4, root.foreground, 0.9)
        hand(seconds * Math.PI / 30 - Math.PI / 2, radius * 0.82, 2, root.accent, 1)

        ctx.fillStyle = root.accent
        ctx.globalAlpha = 1
        ctx.beginPath()
        ctx.arc(cx, cy, 5, 0, Math.PI * 2)
        ctx.fill()
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(330)
      spacing: Style.space(8)

      Text {
        width: parent.width
        text: Qt.formatTime(root.now, "HH:mm:ss")
        color: root.foreground
        font.family: "monospace"
        font.pixelSize: Math.max(Style.font.displayLarge, Style.space(52))
        font.bold: true
        textFormat: Text.PlainText
      }

      Text {
        width: parent.width
        text: ("LOCAL TIME // " + Qt.formatDate(root.now, "dddd, MMMM d")).toUpperCase()
        color: root.foreground
        opacity: 0.72
        font.family: "monospace"
        font.pixelSize: Style.font.title
        textFormat: Text.PlainText
      }

      Rectangle {
        width: parent.width
        height: Math.max(1, Style.space(1))
        color: root.borderColor
      }

      Text {
        width: parent.width
        text: Qt.formatDateTime(root.now, "t") || Qt.locale().name
        color: root.foreground
        opacity: 0.5
        font.family: "monospace"
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }
    }
  }
}
