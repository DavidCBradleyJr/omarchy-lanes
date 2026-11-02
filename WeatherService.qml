import QtQuick
import Quickshell
import Quickshell.Io
import "ShadeModel.js" as ShadeModel

// Shared weather data for every monitor's shade. Instantiated once (Taskbar)
// and handed to each ShadeWeather. Nothing is read or fetched until a view
// first calls refreshIfStale(); views call it when shown and on a timer while
// shown, and the staleness check keeps several monitors from double-fetching.
Item {
  id: root
  visible: false

  property string locationName: "Locating..."
  property real latitude: NaN
  property real longitude: NaN
  property var report: null
  property string radarHost: "https://tilecache.rainviewer.com"
  property var radarFrames: []
  property real lastRefresh: 0
  readonly property int refreshInterval: 15 * 60 * 1000
  readonly property bool hasCoordinates: isFinite(latitude) && isFinite(longitude)
  readonly property bool imperial: Qt.locale().measurementSystem === Locale.ImperialUSSystem

  // Flips on the first refreshIfStale(); until then the location file is not
  // even read.
  property bool started: false

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
    lastRefresh = Date.now()
    if (!radarIndex.running) radarIndex.running = true
  }

  // Called by a weather view when it is shown. The first call starts the
  // service (location lookup, then the fetches); later calls refresh only if
  // the data is older than the interval (with a little slack so a view's
  // interval timer is not skipped by a few ms of jitter).
  function refreshIfStale() {
    if (!started) {
      started = true
      return
    }
    if (hasCoordinates) {
      if (Date.now() - lastRefresh > refreshInterval - 10000) refresh()
    } else if (!locator.running) {
      // The earlier lookup failed or found nothing: try again.
      locationFile.reload()
    }
  }

  FileView {
    id: locationFile
    path: root.started ? Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json" : ""
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
        } catch (e) {}
      }
    }
  }
}
