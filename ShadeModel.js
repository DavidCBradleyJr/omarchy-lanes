.pragma library

var TILE_SIZE = 256
var RADAR_MIN_ZOOM = 4
var RADAR_MAX_ZOOM = 7

function pad2(value) {
  var n = Math.floor(Number(value) || 0)
  return (n < 10 ? "0" : "") + n
}

function dateKey(year, month, day) {
  return year + "-" + pad2(month + 1) + "-" + pad2(day)
}

function monthGrid(year, month, weekStart, todayKey) {
  var first = new Date(year, month, 1)
  var start = ((Number(weekStart) || 0) % 7 + 7) % 7
  var offset = (first.getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - offset)
  var out = []
  for (var i = 0; i < 42; i++) {
    var key = dateKey(cursor.getFullYear(), cursor.getMonth(), cursor.getDate())
    out.push({
      key: key,
      day: cursor.getDate(),
      month: cursor.getMonth(),
      year: cursor.getFullYear(),
      current: cursor.getMonth() === month,
      today: key === todayKey,
      weekend: cursor.getDay() === 0 || cursor.getDay() === 6
    })
    cursor.setDate(cursor.getDate() + 1)
  }
  return out
}

function stepMonth(year, month, delta) {
  var d = new Date(year, month + delta, 1)
  return { year: d.getFullYear(), month: d.getMonth() }
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, Number(value) || 0))
}

function formatDuration(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var minutes = Math.floor(total / 60)
  var secs = total % 60
  return minutes + ":" + pad2(secs)
}

function weatherIcon(code, isDay) {
  var c = Number(code)
  if (c === 0) return isDay === 0 ? "󰖔" : "󰖙"
  if (c === 1 || c === 2) return isDay === 0 ? "󰼱" : "󰖕"
  if (c === 3) return "󰖐"
  if (c === 45 || c === 48) return "󰖑"
  if ((c >= 51 && c <= 57) || (c >= 61 && c <= 67) || (c >= 80 && c <= 82)) return "󰖗"
  if ((c >= 71 && c <= 77) || (c >= 85 && c <= 86)) return "󰖘"
  if (c >= 95) return "󰖓"
  return "󰖐"
}

function weatherLabel(code) {
  var c = Number(code)
  if (c === 0) return "Clear"
  if (c === 1) return "Mostly clear"
  if (c === 2) return "Partly cloudy"
  if (c === 3) return "Overcast"
  if (c === 45 || c === 48) return "Fog"
  if (c >= 51 && c <= 57) return "Drizzle"
  if (c >= 61 && c <= 67) return "Rain"
  if (c >= 71 && c <= 77) return "Snow"
  if (c >= 80 && c <= 82) return "Rain showers"
  if (c >= 85 && c <= 86) return "Snow showers"
  if (c >= 95) return "Thunderstorms"
  return "Conditions unavailable"
}

function radarFrames(data, limit) {
  var source = data && data.radar && Array.isArray(data.radar.past) ? data.radar.past : []
  var frames = []
  for (var i = 0; i < source.length; i++) {
    var frame = source[i]
    var time = Number(frame && frame.time)
    var path = frame && typeof frame.path === "string" ? frame.path : ""
    if (path && isFinite(time) && time > 0)
      frames.push({ path: path, time: time })
  }
  frames.sort(function(a, b) { return a.time - b.time })
  var count = Math.max(1, Math.floor(Number(limit) || frames.length || 1))
  return frames.slice(Math.max(0, frames.length - count))
}

function mercatorPoint(latitude, longitude, zoom) {
  var lat = clamp(latitude, -85.05112878, 85.05112878)
  var lon = Number(longitude) || 0
  var scale = Math.pow(2, zoom)
  var sin = Math.sin(lat * Math.PI / 180)
  return {
    x: ((lon + 180) / 360) * scale,
    y: (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * scale
  }
}

function radarTiles(latitude, longitude, zoom, columns, rows) {
  var point = mercatorPoint(latitude, longitude, zoom)
  var left = Math.floor(point.x) - Math.floor(columns / 2)
  var top = Math.floor(point.y) - Math.floor(rows / 2)
  var max = Math.pow(2, zoom)
  var out = []
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      var tileX = (left + column + max) % max
      var tileY = Math.max(0, Math.min(max - 1, top + row))
      out.push({ x: tileX, y: tileY, column: column, row: row })
    }
  }
  return out
}

function radarMarker(latitude, longitude, zoom, columns, rows) {
  var point = mercatorPoint(latitude, longitude, zoom)
  var left = Math.floor(point.x) - Math.floor(columns / 2)
  var top = Math.floor(point.y) - Math.floor(rows / 2)
  return {
    x: (point.x - left) * TILE_SIZE,
    y: (point.y - top) * TILE_SIZE
  }
}
