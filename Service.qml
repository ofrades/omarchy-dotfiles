import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property string homeDir: Quickshell.env("HOME") || ""

  property bool miseInstalled: false
  property string miseVersion: ""
  property var files: []
  property var edits: []
  property bool historyEnabled: false
  property int trackedEntries: 0
  property int trackedFiles: 0
  property int checkpoints: 0
  property var latest: null
  property string watcher: ""
  property int pendingOperations: 0

  property string origin: ""
  property string branch: ""
  property string syncMode: ""
  property var pendingApplications: []
  property var conflicts: []
  property string syncError: ""
  property string lastPublish: ""
  property string lastFetch: ""

  property var activity: []

  property bool tailscaleInstalled: false
  property bool tailscaleRunning: false
  property string selfName: ""
  property var selfIps: []
  property var peers: []

  property bool refreshing: false
  property string actionStatus: ""
  property string lastError: ""

  readonly property bool watcherRunning: watcher === "running"
  readonly property bool configured: miseInstalled && files.length > 0
  readonly property int unsavedCount: edits.length
  readonly property bool busy: statusProcess.running || actionProcess.running
  readonly property string helperPath: String(Qt.resolvedUrl("dotfiles_status.py")).replace("file://", "")

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 3600)

  property string _statusOutput: ""
  property string _statusError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _actionLabel: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = ["python3", helperPath]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Failed to read dotfiles status"
      return
    }
    miseInstalled = parsed.mise.installed
    miseVersion = parsed.mise.version
    files = parsed.files
    edits = parsed.edits
    historyEnabled = parsed.history.enabled
    trackedEntries = parsed.history.trackedEntries
    trackedFiles = parsed.history.trackedFiles
    checkpoints = parsed.history.checkpoints
    latest = parsed.history.latest
    watcher = parsed.history.watcher
    pendingOperations = parsed.history.pendingOperations
    origin = parsed.sync.origin
    branch = parsed.sync.branch
    syncMode = parsed.sync.mode
    pendingApplications = parsed.sync.pendingApplications
    conflicts = parsed.sync.conflicts
    syncError = parsed.sync.lastError
    lastPublish = parsed.sync.lastPublish
    lastFetch = parsed.sync.lastFetch
    activity = parsed.activity
    tailscaleInstalled = parsed.tailscale.installed
    tailscaleRunning = parsed.tailscale.running
    selfName = parsed.tailscale.selfName
    selfIps = parsed.tailscale.selfIps
    peers = parsed.tailscale.peers
    // A sync-level error is worth surfacing; the helper's own error only
    // matters when we have nothing else to show.
    if (parsed.sync.lastError !== "") lastError = Model.elideStatus(parsed.sync.lastError)
    else if (parsed.lastError !== "" && !parsed.mise.installed) lastError = Model.elideStatus(parsed.lastError)
    else if (lastError !== "" && parsed.lastError === "") lastError = ""
  }

  function elideStatus(text) {
    return Model.elideStatus(text)
  }

  function expandPath(path) {
    var value = String(path || "").trim()
    if (value === "") return ""
    if (value === "~") return homeDir
    if (value.indexOf("~/") === 0 && homeDir !== "") return homeDir + value.substring(1)
    return value
  }

  function runAction(label, command) {
    if (actionProcess.running || !command || command.length === 0) return
    _actionLabel = label
    _actionOutput = ""
    _actionError = ""
    actionStatus = label
    actionProcess.command = command
    actionProcess.running = true
  }

  function track(path) {
    var expanded = expandPath(path)
    if (expanded === "") {
      lastError = "Enter a path like ~/.zshrc first"
      return
    }
    runAction("Tracking " + String(path), ["mise", "-y", "bootstrap", "dotfiles", "track", expanded])
  }

  function untrack(path) {
    var expanded = expandPath(path)
    if (expanded === "") return
    runAction("Untracking " + String(path), ["mise", "-y", "bootstrap", "dotfiles", "untrack", expanded])
  }

  function saveOne(path) {
    var expanded = expandPath(path)
    if (expanded === "") return
    runAction("Saving " + String(path), ["mise", "-y", "bootstrap", "dotfiles", "save", expanded])
  }

  function saveAll() {
    runAction("Saving checkpoints", ["mise", "-y", "bootstrap", "dotfiles", "save"])
  }

  function rollback(path) {
    var expanded = expandPath(path)
    if (expanded === "") return
    runAction("Rolling back " + String(path), ["mise", "-y", "bootstrap", "dotfiles", "rollback", expanded])
  }

  function undo() {
    runAction("Undoing last change", ["mise", "-y", "bootstrap", "dotfiles", "undo"])
  }

  function syncNow() {
    runAction("Checking remote", ["mise", "-y", "bootstrap", "dotfiles", "sync", "--best-effort"])
  }

  function pullNow() {
    runAction("Pulling shared changes", ["mise", "-y", "bootstrap", "dotfiles", "pull"])
  }

  function takeRemote(path) {
    var expanded = expandPath(path)
    if (expanded === "") return
    runAction("Taking remote version of " + String(path), ["mise", "-y", "bootstrap", "dotfiles", "pull", "--take-remote", expanded])
  }

  function keepLocal(path) {
    var expanded = expandPath(path)
    if (expanded === "") return
    runAction("Keeping local version of " + String(path), ["mise", "-y", "bootstrap", "dotfiles", "pull", "--keep-local", expanded])
  }

  function enableWatcher() {
    runAction("Enabling history watcher", ["mise", "-y", "bootstrap", "services", "apply"])
  }

  function setOrigin(url) {
    var value = String(url || "").trim()
    if (value === "") {
      lastError = "Enter a git URL reachable over Tailscale first"
      return
    }
    runAction("Connecting origin", ["mise", "-y", "bootstrap", "dotfiles", "origin", "set", value, "--sync", "sync"])
  }

  function removeOrigin() {
    runAction("Disconnecting origin", ["mise", "-y", "bootstrap", "dotfiles", "origin", "--remove"])
  }

  function tailSendMany(paths, peer) {
    var target = Model.peerTarget(peer)
    if (target === "") {
      lastError = "Pick an online Tailscale machine first"
      return
    }
    var expanded = []
    var count = paths ? paths.length : 0
    for (var i = 0; i < count; i++) {
      var one = expandPath(paths[i])
      if (one !== "") expanded.push(one)
    }
    if (expanded.length === 0) {
      lastError = "Pick a file to send first"
      return
    }
    var name = peer ? String(peer.hostName || "") : ""
    var label = expanded.length === 1 ? ("Sending to " + name) : ("Sending " + expanded.length + " files to " + name)
    var command = ["tailscale", "file", "cp"].concat(expanded, [target])
    runAction(label, command)
  }

  function tailSend(path, peer) {
    tailSendMany([path], peer)
  }

  function tailSendAll(peer) {
    var paths = []
    for (var i = 0; i < files.length; i++) {
      if (files[i] && files[i].target) paths.push(files[i].target)
    }
    if (paths.length === 0) {
      lastError = "Nothing tracked yet"
      return
    }
    tailSendMany(paths, peer)
  }

  // Hand a tracked file to Omarchy's own editor launcher. It already knows the
  // configured default editor and opens a terminal first when that editor is a
  // TUI one, so this panel does not have to guess between nvim and Zed.
  //
  // Deliberately not runAction(): this is a launcher, not a tracked operation.
  // It must not flip `busy` (the panel would grey out while the editor is open)
  // and there is no status worth reporting.
  function openEditor(path) {
    var expanded = expandPath(path)
    if (expanded === "") return
    editorProcess.command = ["omarchy-launch-editor", expanded]
    editorProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 1000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2600
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else root.lastError = Model.elideStatus(stderr || stdout || "Could not read dotfiles status")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) {
        root.lastError = Model.elideStatus(stderr || stdout || (root._actionLabel + " failed"))
        // Keep command stderr in the error channel only. Mirroring it into
        // actionStatus makes the panel render the same failure twice until
        // the delayed status refresh replaces it with mise's concise error.
        root.actionStatus = ""
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root._actionLabel = ""
      delayedRefresh.restart()
    }
  }

  // Fire-and-forget launcher for "open this file in the default editor".
  // omarchy-launch-editor detaches its child (setsid for GUI editors, a fresh
  // terminal for TUI ones), so this exits almost immediately. Output is
  // collected only to keep it off the shell's own stdout.
  Process {
    id: editorProcess
    running: false
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }
}
