// Shared parsing and formatting for the dotfiles plugin.
// Mirrors the structure of the first-party dropbox Model.js: pure
// functions, no shell access, testable with plain node.

var IMAGE_EXTENSIONS = {
  jpg: true, jpeg: true, png: true, gif: true, webp: true, avif: true,
  svg: true, bmp: true, tif: true, tiff: true
}

var VIDEO_EXTENSIONS = {
  mp4: true, mov: true, mkv: true, webm: true, avi: true, m4v: true,
  mpg: true, mpeg: true, wmv: true
}

var DOCUMENT_EXTENSIONS = {
  pdf: true, txt: true, md: true, doc: true, docx: true, xls: true,
  xlsx: true, ppt: true, pptx: true, odt: true, ods: true, odp: true,
  rtf: true, csv: true, lua: true, toml: true, yml: true, yaml: true,
  json: true, js: true, ts: true, sh: true, vim: true
}

function defaultStatus() {
  return {
    ok: true,
    mise: { installed: false, version: "" },
    files: [],
    edits: [],
    history: {
      enabled: false, trackedEntries: 0, trackedFiles: 0, checkpoints: 0,
      latest: null, watcher: "", pendingOperations: 0
    },
    sync: {
      origin: "", branch: "", mode: "", pendingApplications: [],
      conflicts: [], lastError: "", lastPublish: "", lastFetch: ""
    },
    activity: [],
    tailscale: {
      installed: false, running: false, selfName: "", selfIps: [], peers: []
    },
    lastError: ""
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()
    var base = defaultStatus()
    if (parsed.mise && typeof parsed.mise === "object") {
      base.mise.installed = parsed.mise.installed === true
      base.mise.version = String(parsed.mise.version || "")
    }
    if (Array.isArray(parsed.files)) {
      base.files = parsed.files.map(function(entry) {
        return {
          target: String(entry.target || ""),
          mode: String(entry.mode || ""),
          state: String(entry.state || "")
        }
      })
    }
    if (Array.isArray(parsed.edits)) {
      base.edits = parsed.edits.map(function(item) { return String(item) })
    }
    if (parsed.history && typeof parsed.history === "object") {
      var history = parsed.history
      base.history.enabled = history.enabled === true
      base.history.trackedEntries = Number(history.trackedEntries || 0)
      base.history.trackedFiles = Number(history.trackedFiles || 0)
      base.history.checkpoints = Number(history.checkpoints || 0)
      base.history.latest = history.latest || null
      base.history.watcher = String(history.watcher || "")
      base.history.pendingOperations = Number(history.pendingOperations || 0)
    }
    if (parsed.sync && typeof parsed.sync === "object") {
      var sync = parsed.sync
      base.sync.origin = String(sync.origin || "")
      base.sync.branch = String(sync.branch || "")
      base.sync.mode = String(sync.mode || "")
      if (Array.isArray(sync.pendingApplications)) {
        base.sync.pendingApplications = sync.pendingApplications.map(String)
      }
      if (Array.isArray(sync.conflicts)) {
        base.sync.conflicts = sync.conflicts.map(function(item) {
          if (item && typeof item === "object") {
            return { path: String(item.path || ""), reason: String(item.reason || "") }
          }
          return { path: String(item || ""), reason: "" }
        })
      }
      base.sync.lastError = String(sync.lastError || "")
      base.sync.lastPublish = String(sync.lastPublish || "")
      base.sync.lastFetch = String(sync.lastFetch || "")
    }
    if (Array.isArray(parsed.activity)) {
      base.activity = parsed.activity.map(function(item) {
        return {
          id: item.id,
          createdAt: String(item.createdAt || ""),
          trigger: String(item.trigger || ""),
          description: String(item.description || "Checkpoint")
        }
      })
    }
    if (parsed.tailscale && typeof parsed.tailscale === "object") {
      var tail = parsed.tailscale
      base.tailscale.installed = tail.installed === true
      base.tailscale.running = tail.running === true
      base.tailscale.selfName = String(tail.selfName || "")
      if (Array.isArray(tail.selfIps)) {
        base.tailscale.selfIps = tail.selfIps.map(String)
      }
      if (Array.isArray(tail.peers)) {
        base.tailscale.peers = tail.peers.map(function(peer) {
          return {
            hostName: String(peer.hostName || "unknown"),
            dnsName: String(peer.dnsName || ""),
            os: String(peer.os || ""),
            online: peer.online === true,
            ips: Array.isArray(peer.ips) ? peer.ips.map(String) : []
          }
        })
      }
    }
    base.lastError = String(parsed.lastError || "")
    return base
  } catch (e) {
    var failed = defaultStatus()
    failed.ok = false
    failed.lastError = "Failed to parse dotfiles status"
    return failed
  }
}

function fileExtension(name) {
  var value = String(name || "").toLowerCase()
  var index = value.lastIndexOf(".")
  return index >= 0 ? value.substring(index + 1) : ""
}

function fileKind(name) {
  var ext = fileExtension(name)
  if (IMAGE_EXTENSIONS[ext]) return "image"
  if (VIDEO_EXTENSIONS[ext]) return "video"
  if (DOCUMENT_EXTENSIONS[ext]) return "document"
  return "misc"
}

function fileGlyph(name) {
  var kind = fileKind(name)
  if (kind === "image") return "󰋩"
  if (kind === "video") return "󰈫"
  if (kind === "document") return "󰈙"
  return "󰈔"
}

function stateLabel(state) {
  var value = String(state || "")
  if (value === "tracked") return "Tracked"
  if (value === "") return "Unknown"
  return value.charAt(0).toUpperCase() + value.slice(1)
}

function triggerLabel(trigger) {
  var value = String(trigger || "")
  if (value === "edit") return "Auto-save"
  if (value === "save") return "Saved"
  if (value === "") return "Checkpoint"
  return value.charAt(0).toUpperCase() + value.slice(1)
}

function relativeTime(isoText, nowMs) {
  var stamp = Date.parse(String(isoText || ""))
  if (isNaN(stamp)) return ""
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var diff = Math.max(0, Math.floor((now - stamp) / 1000))
  if (diff < 60) return "Just now"
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(days / 365) + "y ago"
}

function peerTarget(peer) {
  if (!peer) return ""
  var name = String(peer.hostName || "").trim()
  if (name !== "" && name !== "unknown") return name + ":"
  var ips = peer.ips || []
  if (ips.length > 0) return String(ips[0]) + ":"
  return ""
}

function peerLabel(peer) {
  if (!peer) return ""
  var name = String(peer.hostName || "unknown")
  var ips = peer.ips || []
  var detail = ips.length > 0 ? String(ips[0]) : String(peer.os || "")
  if (detail !== "") return name + " · " + detail
  return name
}

function elideStatus(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > 140 ? value.substring(0, 137) + "…" : value
}

function isConfigured(parsed) {
  return parsed.mise.installed === true && parsed.files.length > 0
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    defaultStatus: defaultStatus,
    fileExtension: fileExtension,
    fileKind: fileKind,
    fileGlyph: fileGlyph,
    stateLabel: stateLabel,
    triggerLabel: triggerLabel,
    relativeTime: relativeTime,
    peerTarget: peerTarget,
    peerLabel: peerLabel,
    elideStatus: elideStatus,
    isConfigured: isConfigured
  }
}
