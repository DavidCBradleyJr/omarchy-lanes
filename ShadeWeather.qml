import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ShadeModel.js" as ShadeModel

Item {
  id: root

  property color foreground: Color.popups.text
  property color accent: Color.accent
  property color borderColor: Color.popups.border
  property color surfaceColor: Color.popups.background
  property string locationName: "Locating..."
  property real latitude: NaN
  property real longitude: NaN
  property var report: null
  property string radarHost: "https://tilecache.rainviewer.com"
  property var radarFrames: []
  property int radarFrameIndex: -1
  property bool radarPlaying: false
  property int radarZoom: 6
  property int radarSettledTiles: 0
  readonly property bool hasCoordinates: isFinite(latitude) && isFinite(longitude)
  readonly property bool imperial: Qt.locale().measurementSystem === Locale.ImperialUSSystem
  readonly property var current: report && report.current ? report.current : null
  readonly property var daily: buildDaily()
  readonly property var radarFrame: radarFrameIndex >= 0 && radarFrameIndex < radarFrames.length ? radarFrames[radarFrameIndex] : null
  readonly property string radarPath: radarFrame ? radarFrame.path : ""
  readonly property string radarTime: radarFrame ? Qt.formatTime(new Date(radarFrame.time * 1000), "h:mm AP") : ""
  readonly property int radarColumns: 4
  readonly property int radarRows: 3
  readonly property var tiles: hasCoordinates ? ShadeModel.radarTiles(latitude, longitude, radarZoom, radarColumns, radarRows) : []
  readonly property var marker: hasCoordinates ? ShadeModel.radarMarker(latitude, longitude, radarZoom, radarColumns, radarRows) : ({ x: 0, y: 0 })
  readonly property int radarExpectedTiles: radarFrames.length * tiles.length
  readonly property bool radarPreloaded: radarExpectedTiles > 0 && radarSettledTiles >= radarExpectedTiles
  readonly property int radarPreloadPercent: radarExpectedTiles > 0
    ? Math.min(100, Math.round(radarSettledTiles * 100 / radarExpectedTiles)) : 0

  function buildDaily() {
    if (!report || !report.daily || !report.daily.time) return []
    var out = []
    for (var i = 0; i < Math.min(5, report.daily.time.length); i++) {
      out.push({
        date: report.daily.time[i],
        code: report.daily.weather_code[i],
        high: report.daily.temperature_2m_max[i],
        low: report.daily.temperature_2m_min[i]
      })
    }
    return out
  }

  function loadConfiguredLocation(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      var lat = parseFloat(data.latitude)
      var lon = parseFloat(data.longitude)
      if (isFinite(lat) && isFinite(lon)) {
        locationName = String(data.name || "Local weather")
        latitude = lat
        longitude = lon
        refresh()
        return
      }
    } catch (e) {}
    if (!locator.running) locator.running = true
  }

  function refresh() {
    if (!hasCoordinates || forecast.running) return
    var units = imperial
      ? "&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch"
      : "&temperature_unit=celsius&wind_speed_unit=kmh&precipitation_unit=mm"
    forecast.command = ["curl", "-fsS", "--max-time", "8",
      "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(latitude)
      + "&longitude=" + encodeURIComponent(longitude)
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m,is_day"
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=5&timezone=auto" + units]
    forecast.running = true
    if (!radarIndex.running) radarIndex.running = true
  }

  function setRadarZoom(value) {
    radarPlaying = false
    radarZoom = ShadeModel.clamp(Math.round(value), ShadeModel.RADAR_MIN_ZOOM, ShadeModel.RADAR_MAX_ZOOM)
  }

  function stepRadar(delta) {
    if (radarFrames.length < 1) return
    radarFrameIndex = (radarFrameIndex + delta + radarFrames.length) % radarFrames.length
  }

  FileView {
    id: locationFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfiguredLocation(text())
    onLoadFailed: if (!locator.running) locator.running = true
    onFileChanged: reload()
  }

  Process {
    id: locator
    command: ["curl", "-fsS", "--max-time", "8", "https://wttr.in/?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          var area = parsed.nearest_area && parsed.nearest_area[0]
          if (!area) return
          root.latitude = parseFloat(area.latitude)
          root.longitude = parseFloat(area.longitude)
          root.locationName = area.areaName && area.areaName[0] ? area.areaName[0].value : "Local weather"
          root.refresh()
        } catch (e) {
          root.locationName = "Weather unavailable"
        }
      }
    }
  }

  Process {
    id: forecast
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.report = JSON.parse(String(text || "{}")) } catch (e) {}
      }
    }
  }

  Process {
    id: radarIndex
    command: ["curl", "-fsS", "--max-time", "8", "https://api.rainviewer.com/public/weather-maps.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          var frames = ShadeModel.radarFrames(data, 10)
          if (frames.length === 0) return
          root.radarHost = data.host || root.radarHost
          root.radarFrames = frames
          root.radarFrameIndex = frames.length - 1
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 900
    running: root.radarPlaying && root.radarFrames.length > 1
    repeat: true
    onTriggered: root.stepRadar(1)
  }

  Timer {
    interval: 15 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Row {
    anchors.fill: parent
    spacing: Style.space(24)

    Column {
      width: Math.min(Style.space(420), parent.width * 0.42)
      height: parent.height
      spacing: Style.space(8)

      Text {
        width: parent.width
        text: "WX // " + root.locationName.toUpperCase()
        color: root.foreground
        font.family: "monospace"
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Row {
        spacing: Style.space(14)
        height: Style.space(82)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.current ? ShadeModel.weatherIcon(root.current.weather_code, root.current.is_day) : "󰖐"
          color: root.foreground
          font.family: "monospace"
          font.pixelSize: Style.space(52)
          textFormat: Text.PlainText
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: root.current ? Math.round(root.current.temperature_2m) + "°" : "--"
            color: root.foreground
            font.family: "monospace"
            font.pixelSize: Style.space(40)
            font.bold: true
            textFormat: Text.PlainText
          }
          Text {
            text: root.current ? ShadeModel.weatherLabel(root.current.weather_code) : "Loading conditions"
            color: root.foreground
            opacity: 0.6
            font.family: "monospace"
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }
        }
      }

      Text {
        width: parent.width
        text: root.current
          ? "Feels " + Math.round(root.current.apparent_temperature) + "°   Humidity " + Math.round(root.current.relative_humidity_2m) + "%   Wind " + Math.round(root.current.wind_speed_10m) + " " + (root.imperial ? "mph" : "km/h")
          : ""
        color: root.foreground
        opacity: 0.52
        font.family: "monospace"
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
      }

      Rectangle {
        width: parent.width
        height: Math.max(1, Style.space(1))
        color: root.borderColor
      }

      Repeater {
        model: root.daily

        Item {
          required property var modelData
          width: parent.width
          height: Style.space(36)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(82)
            text: Qt.formatDate(new Date(parent.modelData.date + "T12:00:00"), "ddd")
            color: root.foreground
            opacity: 0.7
            font.family: "monospace"
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: ShadeModel.weatherIcon(parent.modelData.code, 1)
            color: root.foreground
            font.family: "monospace"
            font.pixelSize: Style.font.iconLarge
            textFormat: Text.PlainText
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(parent.modelData.high) + "°  " + Math.round(parent.modelData.low) + "°"
            color: root.foreground
            font.family: "monospace"
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
        }
      }
    }

    Rectangle {
      id: radar
      width: parent.width - parent.spacing - Math.min(Style.space(420), parent.width * 0.42)
      height: parent.height
      radius: 0
      color: "#101820"
      border.width: Math.max(1, Style.space(1))
      border.color: root.borderColor
      clip: true

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
          if (wheel.angleDelta.y !== 0)
            root.setRadarZoom(root.radarZoom + (wheel.angleDelta.y > 0 ? 1 : -1))
          wheel.accepted = true
        }
      }

      Item {
        id: tileCanvas
        width: root.radarColumns * ShadeModel.TILE_SIZE
        height: root.radarRows * ShadeModel.TILE_SIZE
        x: Math.round(radar.width / 2 - root.marker.x)
        y: Math.round(radar.height / 2 - root.marker.y)

        Repeater {
          model: root.tiles

          Item {
            id: tileCell
            required property var modelData
            x: modelData.column * ShadeModel.TILE_SIZE
            y: modelData.row * ShadeModel.TILE_SIZE
            width: ShadeModel.TILE_SIZE
            height: ShadeModel.TILE_SIZE

            Image {
              anchors.fill: parent
              source: "https://services.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/"
                + root.radarZoom + "/" + parent.modelData.y + "/" + parent.modelData.x
              asynchronous: true
              cache: true
            }
            Repeater {
              model: root.radarFrames

              Image {
                required property var modelData
                required property int index
                property bool countedSettled: false

                function syncSettled() {
                  var settled = status === Image.Ready || status === Image.Error
                  if (settled === countedSettled) return
                  countedSettled = settled
                  root.radarSettledTiles += settled ? 1 : -1
                }

                anchors.fill: parent
                visible: index === root.radarFrameIndex
                source: root.radarHost + modelData.path + "/256/" + root.radarZoom + "/" + tileCell.modelData.x + "/" + tileCell.modelData.y + "/2/1_1.png"
                asynchronous: true
                cache: true
                onStatusChanged: syncSettled()
                Component.onCompleted: syncSettled()
                Component.onDestruction: if (countedSettled) root.radarSettledTiles--
              }
            }
          }
        }

        Rectangle {
          x: root.marker.x - width / 2
          y: root.marker.y - height / 2
          width: Style.space(13)
          height: width
          radius: width / 2
          color: root.accent
          border.width: Math.max(1, Style.space(2))
          border.color: root.foreground
        }
      }

      Canvas {
        id: radarScope
        anchors.fill: parent
        opacity: 0.58
        property var markerPosition: root.marker
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onMarkerPositionChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = tileCanvas.x + root.marker.x
          var cy = tileCanvas.y + root.marker.y
          var maxRadius = Math.min(width, height) * 0.48
          ctx.strokeStyle = root.foreground
          ctx.lineWidth = 1

          for (var i = 1; i <= 4; i++) {
            ctx.globalAlpha = 0.22
            ctx.beginPath()
            ctx.arc(cx, cy, maxRadius * i / 4, 0, Math.PI * 2)
            ctx.stroke()
          }

          ctx.globalAlpha = 0.18
          ctx.beginPath()
          ctx.moveTo(0, cy)
          ctx.lineTo(width, cy)
          ctx.moveTo(cx, 0)
          ctx.lineTo(cx, height)
          ctx.stroke()
        }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Style.space(10)
        width: radarLabel.implicitWidth + Style.space(16)
        height: radarLabel.implicitHeight + Style.space(8)
        radius: 0
        color: root.surfaceColor
        border.width: Math.max(1, Style.space(1))
        border.color: root.borderColor
        opacity: 0.88

        Text {
          id: radarLabel
          anchors.centerIn: parent
          text: "RADAR // " + (root.radarTime ? root.radarTime : "ACQUIRING")
          color: root.foreground
          font.family: "monospace"
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }

      Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(12)
        text: "REFLECTIVITY / 0.5° PRECIPITATION"
        color: root.foreground
        opacity: 0.6
        font.family: "monospace"
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      Column {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(4)

        RadarButton {
          label: "+"
          enabled: root.radarZoom < ShadeModel.RADAR_MAX_ZOOM
          onPressed: root.setRadarZoom(root.radarZoom + 1)
        }
        RadarButton {
          label: "Z" + (root.radarZoom < 10 ? "0" : "") + root.radarZoom
          wide: true
          passive: true
        }
        RadarButton {
          label: "-"
          enabled: root.radarZoom > ShadeModel.RADAR_MIN_ZOOM
          onPressed: root.setRadarZoom(root.radarZoom - 1)
        }
      }

      Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.space(12)
        anchors.bottomMargin: Style.space(12)
        spacing: 0

        Repeater {
          model: ["#394b9b", "#296b9f", "#2b9f91", "#55c66b", "#d5c94f", "#d58d3f", "#ca4d4c", "#bd5f9b"]
          Rectangle {
            required property string modelData
            width: Style.space(30)
            height: Style.space(4)
            color: modelData
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(12)
        spacing: Style.space(4)

        RadarButton {
          label: "󰒮"
          enabled: root.radarFrames.length > 1
          onPressed: {
            root.radarPlaying = false
            root.stepRadar(-1)
          }
        }
        RadarButton {
          label: root.radarPlaying ? "󰏤" : "󰐊"
          highlighted: root.radarPlaying
          enabled: root.radarFrames.length > 1 && root.radarPreloaded
          onPressed: root.radarPlaying = !root.radarPlaying
        }
        RadarButton {
          label: "󰒭"
          enabled: root.radarFrames.length > 1
          onPressed: {
            root.radarPlaying = false
            root.stepRadar(1)
          }
        }
        RadarButton {
          label: root.radarTime ? root.radarTime.toUpperCase() : "ACQUIRING"
          wide: true
          passive: true
        }
      }

      Text {
        anchors.centerIn: parent
        visible: !root.hasCoordinates
        text: "Loading radar"
        color: root.foreground
        font.family: "monospace"
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }

      Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(6)
        text: "ESRI DARK CANVAS | RAINVIEWER"
        color: "white"
        opacity: 0.65
        font.family: "monospace"
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }
  }

  component RadarButton: Rectangle {
    id: button
    property string label: ""
    property bool wide: false
    property bool passive: false
    property bool highlighted: false
    signal pressed()

    width: wide ? Math.max(Style.space(62), buttonLabel.implicitWidth + Style.space(16)) : Style.space(34)
    height: Style.space(30)
    radius: 0
    color: highlighted || (!passive && buttonMouse.containsMouse) ? root.surfaceColor : "#b0101820"
    border.width: Math.max(1, Style.space(1))
    border.color: highlighted ? root.accent : root.borderColor
    opacity: enabled ? 1 : 0.35

    Text {
      id: buttonLabel
      anchors.centerIn: parent
      text: button.label
      color: button.highlighted ? root.accent : root.foreground
      font.family: "monospace"
      font.pixelSize: Style.font.caption
      font.bold: button.highlighted
      textFormat: Text.PlainText
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      enabled: button.enabled && !button.passive
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: button.pressed()
    }
  }
}
