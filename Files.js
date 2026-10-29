.pragma library

// Nerd Font (Material Design) glyph and colors.toml color for each kind of file.
var KINDS = [
  { kind: "pdf", glyph: "\u{f0226}", color: "red", ext: ["pdf"] },
  { kind: "image", glyph: "\u{f02e9}", color: "magenta", ext: ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "avif", "bmp"] },
  { kind: "video", glyph: "\u{f0567}", color: "cyan", ext: ["mp4", "mov", "mkv", "webm", "avi"] },
  { kind: "audio", glyph: "\u{f0386}", color: "bright_yellow", ext: ["mp3", "wav", "flac", "m4a", "ogg", "opus"] },
  { kind: "archive", glyph: "\u{f05c4}", color: "orange", ext: ["zip", "tar", "gz", "tgz", "xz", "zst", "7z", "rar", "bz2"] },
  { kind: "sheet", glyph: "\u{f021b}", color: "green", ext: ["csv", "tsv", "xlsx", "xls", "ods", "numbers"] },
  { kind: "slides", glyph: "\u{f0227}", color: "orange", ext: ["pptx", "ppt", "key", "odp"] },
  { kind: "doc", glyph: "\u{f0219}", color: "blue", ext: ["doc", "docx", "odt", "rtf", "txt", "md", "pages"] },
  { kind: "code", glyph: "\u{f022e}", color: "bright_cyan", ext: ["json", "js", "ts", "py", "sh", "html", "css", "yaml", "yml", "toml", "sql"] },
  { kind: "package", glyph: "\u{f03d7}", color: "bright_magenta", ext: ["pkg", "deb", "rpm", "appimage", "dmg", "iso", "exe"] }
]
var GENERIC = { kind: "file", glyph: "\u{f0214}", color: "" }

function kindOf(name) {
  var dot = name.lastIndexOf(".")
  var ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : ""
  for (var i = 0; i < KINDS.length; i++) {
    if (KINDS[i].ext.indexOf(ext) !== -1) return KINDS[i]
  }
  return GENERIC
}

// Parses `find -printf '%T@\t%s\t%p\n'` output into the newest `limit` files.
function parse(raw, limit) {
  var files = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 3) continue
    var path = parts.slice(2).join("\t")
    var name = path.slice(path.lastIndexOf("/") + 1)
    var kind = kindOf(name)
    files.push({
      mtime: parseFloat(parts[0]),
      size: parseInt(parts[1], 10),
      path: path,
      name: name,
      kind: kind.kind,
      glyph: kind.glyph,
      colorKey: kind.color
    })
  }
  files.sort(function(a, b) { return b.mtime - a.mtime })
  return files.slice(0, limit)
}

function humanSize(bytes) {
  var units = ["B", "KB", "MB", "GB"]
  var size = bytes
  var unit = 0
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024
    unit++
  }
  return unit === 0 ? size + " B" : size.toFixed(1) + " " + units[unit]
}

function humanAge(mtime) {
  var seconds = Math.max(0, Date.now() / 1000 - mtime)
  if (seconds < 60) return "just now"
  if (seconds < 3600) return Math.floor(seconds / 60) + "m ago"
  if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago"
  if (seconds < 604800) return Math.floor(seconds / 86400) + "d ago"
  return Qt.formatDate(new Date(mtime * 1000), "MMM d")
}

function fileUri(path) {
  return "file://" + path.split("/").map(encodeURIComponent).join("/")
}

// Reads `key = "#rrggbb"` pairs out of the theme's colors.toml.
function parseColors(raw) {
  var colors = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (match) colors[match[1]] = match[2]
  }
  return colors
}
