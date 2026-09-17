import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Dotfiles popup: setup checklist, tracked files, checkpoint activity,
// and Tailscale sharing. The backend is Service.qml (mise + tailscale
// over QML Process); this file is only layout and wiring.
//
// BarWidget.qml owns the bar slot and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "io.github.ofrades.dotfiles"
  ipcTarget: "io.github.ofrades.dotfiles"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string currentTab: "files"
  property string selectedPath: ""
  property string selectedPeer: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int trackedCount: dotfiles.files.length
  readonly property bool healthy: dotfiles.miseInstalled && dotfiles.watcherRunning
  readonly property string heroMeta: !dotfiles.miseInstalled ? "mise is not installed"
    : trackedCount === 0 ? "Track your first file to begin"
    : trackedCount + (trackedCount === 1 ? " file" : " files") + " · " + dotfiles.checkpoints + " checkpoints"

  function open() {
    if (!dotfiles.configured) currentTab = "setup"
    refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    dotfiles.refresh()
  }

  function showTab(name) {
    currentTab = name
  }

  function selectFile(path) {
    selectedPath = String(path || "")
    if (sendPathInput) sendPathInput.text = selectedPath
  }

  function selectPeer(target) {
    selectedPeer = String(target || "")
  }

  function shareFile(path) {
    var target = String(path || "").trim()
    if (target === "") return
    selectFile(target)
    if (dotfiles.tailscaleRunning && root.selectedPeer !== "") {
      var peer = root.peerByTarget(root.selectedPeer)
      if (peer !== null) {
        dotfiles.tailSend(target, peer)
        return
      }
    }
    root.showTab("share")
  }

  function removeFile(path) {
    var target = String(path || "").trim()
    if (target === "") return
    dotfiles.untrack(target)
    if (root.selectedPath === target) root.selectedPath = ""
  }

  // Close first: the panel is an overlay, and the editor window that is about
  // to appear should not open behind it.
  function editFile(path) {
    var target = String(path || "").trim()
    if (target === "") return
    dotfiles.openEditor(target)
    root.close()
  }

  function shareAllFiles() {
    if (trackedCount === 0) return
    if (dotfiles.tailscaleRunning && root.selectedPeer !== "") {
      var peer = root.peerByTarget(root.selectedPeer)
      if (peer !== null) {
        dotfiles.tailSendAll(peer)
        return
      }
    }
    root.showTab("share")
  }

  function effectiveSendPath() {
    var typed = sendPathInput ? String(sendPathInput.text || "").trim() : ""
    if (typed !== "") return typed
    return selectedPath
  }

  function peerByTarget(target) {
    for (var i = 0; i < dotfiles.peers.length; i++) {
      if (Model.peerTarget(dotfiles.peers[i]) === target) return dotfiles.peers[i]
    }
    return null
  }

  onOpenedChanged: if (opened) {
    if (panelFlick) panelFlick.contentY = 0
    if (!dotfiles.configured) currentTab = "setup"
    dotfiles.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: dotfiles
    settings: root.settings
  }

  // IPC is handled by BarWidget.qml (the bar-widget entry point), which
  // forwards open/close/toggle here. A second IpcHandler on the same
  // target would only conflict, so this panel exposes none.

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") dotfiles.refresh()
        else if (t === "1") root.showTab("setup")
        else if (t === "2") root.showTab("files")
        else if (t === "3") root.showTab("activity")
        else if (t === "4") root.showTab("share")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Dotfiles"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.healthy ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰈙"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          // View switcher as bordered pills, same as the wifi panel's
          // band/DNS pills: `active` fills the current view.
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Setup"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: root.currentTab === "setup"
              Layout.fillWidth: true
              Layout.preferredWidth: 100
              onClicked: root.showTab("setup")
            }

            Button {
              text: "Files"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: root.currentTab === "files"
              Layout.fillWidth: true
              Layout.preferredWidth: 100
              onClicked: root.showTab("files")
            }

            Button {
              text: "Activity"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: root.currentTab === "activity"
              Layout.fillWidth: true
              Layout.preferredWidth: 100
              onClicked: root.showTab("activity")
            }

            Button {
              text: "Share"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: root.currentTab === "share"
              Layout.fillWidth: true
              Layout.preferredWidth: 100
              onClicked: root.showTab("share")
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: dotfiles.actionStatus !== "" || dotfiles.lastError !== ""
            width: parent.width
            text: dotfiles.actionStatus !== "" ? dotfiles.actionStatus : dotfiles.lastError
            color: dotfiles.lastError !== "" && dotfiles.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ---- Setup tab
          Column {
            visible: root.currentTab === "setup"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "SETUP"; foreground: root.foreground; fontFamily: root.fontFamily }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap
              InfoPair { label: "Mise"; value: dotfiles.miseInstalled ? dotfiles.miseVersion : "Not installed" }
              InfoPair { label: "Watcher"; value: dotfiles.historyEnabled ? (dotfiles.watcherRunning ? "Running" : "Stopped (" + dotfiles.watcher + ")") : "No history yet" }
              InfoPair { label: "Tracked"; value: dotfiles.trackedEntries + " entries · " + dotfiles.trackedFiles + " files" }
              InfoPair { label: "Origin"; value: dotfiles.origin !== "" ? dotfiles.origin : "Not connected" }
              InfoPair { label: "Tailscale"; value: dotfiles.tailscaleRunning ? (dotfiles.selfName + ", " + dotfiles.peers.length + " peers") : "Offline" }
            }

            Text {
              visible: !dotfiles.miseInstalled
              width: parent.width
              textFormat: Text.PlainText
              text: "Install mise from mise.jdx.dev, then track your first file. This panel wraps `mise bootstrap dotfiles` — files stay in place, history is plain git."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            ActionRow {
              visible: dotfiles.miseInstalled && !dotfiles.watcherRunning
              title: "Enable auto-save watcher"
              subtitle: "Saves checkpoints as files change"
              onClicked: dotfiles.enableWatcher()
            }

            TextField {
              id: originInput
              visible: dotfiles.miseInstalled
              width: parent.width
              placeholderText: "ssh://user@100.x.y.z/~/setup.git"
              text: dotfiles.origin
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              placeholderTextColor: root.dim
              background: Rectangle {
                color: "transparent"
                border.color: root.dim
                border.width: 1
                radius: 6
              }
            }

            ActionRow {
              visible: dotfiles.miseInstalled
              title: dotfiles.origin !== "" ? "Reconnect Tailscale origin" : "Connect Tailscale origin"
              subtitle: "One machine hosts a bare git repo, the rest follow it"
              onClicked: dotfiles.setOrigin(originInput.text)
            }

            ActionRow {
              visible: dotfiles.miseInstalled && dotfiles.origin !== ""
              title: "Disconnect origin"
              subtitle: "Local checkpoints are kept"
              onClicked: dotfiles.removeOrigin()
            }

            ActionRow {
              visible: dotfiles.miseInstalled && trackedCount === 0
              title: "Track your first file"
              subtitle: "Goes to the Files tab"
              onClicked: root.showTab("files")
            }
          }

          // ---- Files tab
          Column {
            visible: root.currentTab === "files"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "TRACKED FILES"; foreground: root.foreground; fontFamily: root.fontFamily }

            // Enter here tracks — that is the whole affordance, so there is
            // deliberately no separate "Track this path" row duplicating it.
            TextField {
              id: newPathInput
              width: parent.width
              placeholderText: "~/.zshrc  —  path to track"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              placeholderTextColor: root.dim
              background: Rectangle {
                color: "transparent"
                border.color: root.dim
                border.width: 1
                radius: 6
              }
              onAccepted: {
                dotfiles.track(text)
                text = ""
              }
            }

            // Same deal as "Sync now" in Activity: the watcher saves on its
            // own, so the manual checkpoint only earns a row when auto-save is
            // actually behind (mise throttles constantly-rewritten files like
            // ~/.config/mise/config.toml to one save a day).
            ActionRow {
              visible: trackedCount > 0 && dotfiles.unsavedCount > 0
              title: "Save all (" + dotfiles.unsavedCount + " unsaved)"
              subtitle: "One checkpoint across every tracked file"
              onClicked: dotfiles.saveAll()
            }

            ActionRow {
              visible: trackedCount > 0
              title: "Share all files"
              subtitle: trackedCount + (trackedCount === 1 ? " file" : " files") + " via Taildrop"
              onClicked: root.shareAllFiles()
            }

            Text {
              visible: trackedCount === 0
              width: parent.width
              textFormat: Text.PlainText
              text: "Nothing tracked yet. Type a path above — e.g. ~/.config/hypr/bindings.lua — and press Enter."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Column {
              visible: trackedCount > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: dotfiles.files
                FileRow {
                  required property var modelData
                  width: parent.width
                  file: modelData
                }
              }
            }

            Column {
              visible: root.selectedPath !== ""
              width: parent.width
              spacing: Style.space(6)

              PanelSeparator { foreground: root.foreground }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "Selected: " + root.selectedPath
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }

              ActionRow {
                title: "Save checkpoint"
                subtitle: root.selectedPath
                onClicked: dotfiles.saveOne(root.selectedPath)
              }

              ActionRow {
                title: "Roll back to last checkpoint"
                subtitle: "Current state is kept, undo reverses this"
                onClicked: dotfiles.rollback(root.selectedPath)
              }

              ActionRow {
                title: "Stop tracking"
                subtitle: "File and its checkpoints stay on disk"
                onClicked: {
                  dotfiles.untrack(root.selectedPath)
                  root.selectedPath = ""
                }
              }
            }
          }

          // ---- Activity tab
          Column {
            visible: root.currentTab === "activity"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "ACTIVITY"; foreground: root.foreground; fontFamily: root.fontFamily }

            // Publishing and fetching belong to the history watcher, so this
            // tab reports where that automation stands and only offers the
            // manual round when the automation is not covering it: watcher
            // stopped, or the last sync failed.
            Text {
              visible: dotfiles.origin !== "" && dotfiles.watcherRunning && dotfiles.syncError === ""
              width: parent.width
              textFormat: Text.PlainText
              text: {
                var parts = ["Syncing automatically"]
                var published = Model.relativeTime(dotfiles.lastPublish)
                var fetched = Model.relativeTime(dotfiles.lastFetch)
                if (published !== "") parts.push("published " + published)
                if (fetched !== "") parts.push("fetched " + fetched)
                return parts.join(" · ")
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            ActionRow {
              visible: dotfiles.origin !== "" && (!dotfiles.watcherRunning || dotfiles.syncError !== "")
              title: "Sync now"
              subtitle: dotfiles.syncError !== "" ? dotfiles.syncError : "Watcher stopped — publish + fetch by hand"
              onClicked: dotfiles.syncNow()
            }

            ActionRow {
              visible: dotfiles.pendingApplications.length > 0 || dotfiles.conflicts.length > 0
              title: "Pull shared changes"
              subtitle: dotfiles.conflicts.length > 0 ? (dotfiles.conflicts.length + " conflicts need a decision") : (dotfiles.pendingApplications.length + " pending")
              onClicked: dotfiles.pullNow()
            }

            ActionRow {
              title: "Undo last change"
              subtitle: "Reverses rollback, pull, or save"
              onClicked: dotfiles.undo()
            }

            Text {
              visible: dotfiles.activity.length === 0
              width: parent.width
              textFormat: Text.PlainText
              text: "No checkpoints yet. Edit a tracked file and the watcher saves one here."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Column {
              visible: dotfiles.activity.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: dotfiles.activity
                ActivityRow {
                  required property var modelData
                  width: parent.width
                  checkpoint: modelData
                }
              }
            }
          }

          // ---- Share tab (Tailscale)
          Column {
            visible: root.currentTab === "share"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "TAILSCALE SHARE"; foreground: root.foreground; fontFamily: root.fontFamily }

            Text {
              visible: !dotfiles.tailscaleRunning
              width: parent.width
              textFormat: Text.PlainText
              text: dotfiles.tailscaleInstalled ? "Tailscale is offline — connect, then reopen." : "Install Tailscale to share machine-to-machine without any cloud account."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              visible: dotfiles.tailscaleRunning
              width: parent.width
              spacing: Style.spacing.labelGap
              InfoPair { label: "This machine"; value: dotfiles.selfName !== "" ? dotfiles.selfName : "unknown" }
            }

            TextField {
              id: sendPathInput
              visible: dotfiles.tailscaleRunning
              width: parent.width
              placeholderText: "File to send — defaults to the selected file"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              placeholderTextColor: root.dim
              background: Rectangle {
                color: "transparent"
                border.color: root.dim
                border.width: 1
                radius: 6
              }
            }

            Column {
              visible: dotfiles.tailscaleRunning
              width: parent.width
              spacing: Style.space(6)

              Text {
                visible: dotfiles.peers.length === 0
                width: parent.width
                textFormat: Text.PlainText
                text: "No tailnet peers found."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
              }

              Repeater {
                model: dotfiles.peers
                PeerRow {
                  required property var modelData
                  width: parent.width
                  peer: modelData
                }
              }
            }

            ActionRow {
              visible: dotfiles.tailscaleRunning && root.selectedPeer !== ""
              title: "Send file to peer"
              subtitle: (root.effectiveSendPath() !== "" ? root.effectiveSendPath() : "pick a file") + " → " + root.selectedPeer
              onClicked: dotfiles.tailSend(root.effectiveSendPath(), root.peerByTarget(root.selectedPeer))
            }

            ActionRow {
              visible: dotfiles.tailscaleRunning && root.selectedPeer !== "" && trackedCount > 0
              title: "Send all tracked files to peer"
              subtitle: trackedCount + (trackedCount === 1 ? " file" : " files") + " → " + root.selectedPeer
              onClicked: dotfiles.tailSendAll(root.peerByTarget(root.selectedPeer))
            }

            // No "Collect received files" row: omarchy-tailscale-receive.service
            // already waits for deliveries and moves them into ~/Downloads, so a
            // manual `tailscale file get` here only raced it for the same inbox.
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Tip: for full history sync, host a bare repo on one machine (`git init --bare ~/setup.git`) and connect it as origin in the Setup tab. Taildrop above is for quick one-off file pushes."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "r refresh · 1–4 switch tabs · Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    signal clicked()

    property string title: ""
    property string subtitle: ""

    // A full-width action row is the whole contract of this component. It has
    // to claim the width itself: the root is a Rectangle (via CursorSurface),
    // which has no implicit width, and a Column does not stretch its children
    // — so without this every ActionRow renders 0px wide inside the panel's
    // Columns and shows up as a blank gap.
    width: parent ? parent.width : 0

    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: enabled && !dotfiles.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: !dotfiles.busy
      onClicked: actionRow.clicked()
    }

    RowLayout {
      id: actionContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.title
          color: root.foreground
          opacity: dotfiles.busy ? 0.5 : 1.0
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          visible: actionRow.subtitle !== ""
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }

      Text {
        textFormat: Text.PlainText
        text: "›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component FileRow: CursorSurface {
    id: fileRow
    property var file: null
    readonly property string target: file ? String(file.target || "") : ""
    readonly property bool isSelected: root.selectedPath !== "" && root.selectedPath === target

    foreground: root.foreground
    implicitHeight: fileContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.selectFile(fileRow.target)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        visible: fileRow.isSelected
        textFormat: Text.PlainText
        text: "●"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        textFormat: Text.PlainText
        text: Model.fileGlyph(fileRow.target)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: fileContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: fileRow.target
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideMiddle
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: (fileRow.file ? String(fileRow.file.mode || "") : "") + " · " + Model.stateLabel(fileRow.file ? fileRow.file.state : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Edit is first, remove stays last: destructive actions keep the
      // outermost position so it never sits next to the other buttons' muscle
      // memory.
      PanelActionButton {
        iconText: "󰏫"
        tooltipText: "Edit " + fileRow.target
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.editFile(fileRow.target)
      }

      PanelActionButton {
        iconText: "󰒊"
        tooltipText: "Share " + fileRow.target + " via Taildrop"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.shareFile(fileRow.target)
      }

      PanelActionButton {
        iconText: "󰅙"
        tooltipText: "Remove " + fileRow.target + " from tracking"
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.removeFile(fileRow.target)
      }
    }
  }

  component ActivityRow: Item {
    property var checkpoint: null

    width: parent.width
    implicitHeight: activityContent.implicitHeight + Style.space(8)

    Column {
      id: activityContent
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        width: parent.width - Style.space(20)
        text: checkpoint ? String(checkpoint.description || "Checkpoint") : "Checkpoint"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width - Style.space(20)
        text: activityMeta()
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    function activityMeta() {
      var cp = checkpoint
      if (!cp) return ""
      var parts = []
      if (cp.id !== undefined && cp.id !== null) parts.push("#" + cp.id)
      var trigger = Model.triggerLabel(cp.trigger)
      if (trigger !== "") parts.push(trigger)
      var when = Model.relativeTime(cp.createdAt)
      if (when !== "") parts.push(when)
      return parts.join(" · ")
    }
  }

  component PeerRow: CursorSurface {
    id: peerRow
    property var peer: null
    readonly property string target: Model.peerTarget(peerRow.peer)
    readonly property bool isSelected: root.selectedPeer !== "" && root.selectedPeer === target
    readonly property bool online: peerRow.peer ? peerRow.peer.online === true : false

    foreground: root.foreground
    implicitHeight: peerContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: peerRow.online ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: peerRow.online
      onClicked: root.selectPeer(peerRow.target)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Rectangle {
        Layout.alignment: Qt.AlignVCenter
        width: Style.space(8)
        height: Style.space(8)
        radius: Style.space(4)
        color: peerRow.online ? root.foreground : root.dim
        opacity: peerRow.online ? 1.0 : 0.4
      }

      ColumnLayout {
        id: peerContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: (peerRow.isSelected ? "● " : "") + Model.peerLabel(peerRow.peer)
          color: peerRow.online ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideMiddle
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: peerRow.online ? "Online — click to select" : "Offline"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideMiddle
  }
}
