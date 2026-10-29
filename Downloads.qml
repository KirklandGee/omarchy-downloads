import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Files.js" as Files

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool dragging: false
  property int selectedIndex: 0
  property int limit: 15
  property string downloadsDir: ""
  property var palette: ({})

  // Shares the [menu] surface tokens, like the built-in emoji picker, so
  // themes that style the menu style this popup too.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property color accent: Commons.Color.accent
  property color dim: Util.alpha(foreground, 0.55)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  property int cardWidth: Style.space(440)
  property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.lg * 3)
  property int iconSize: Math.max(Style.space(34), Style.font.display + Style.spacing.md)
  property int headerHeight: Math.max(Style.space(40), Style.font.title + Style.spacing.controlPaddingY * 3)
  property int footerHeight: Math.max(Style.space(30), Style.font.caption + Style.spacing.lg * 2)
  property int listHeight: Math.max(1, Math.min(fileModel.count, 9)) * rowHeight + Style.spacing.md * 2

  function open(payloadJson) {
    root.selectedIndex = 0
    root.dragging = false
    colorsFile.reload()
    lister.running = true
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.dragging = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "kirklandgee.downloads")
  }

  function loadFiles(raw) {
    var lines = String(raw || "").split("\n")
    root.downloadsDir = lines.shift()
    var files = Files.parse(lines.join("\n"), root.limit)
    fileModel.clear()
    for (var i = 0; i < files.length; i++) fileModel.append(files[i])
    root.selectedIndex = 0
    fileList.positionViewAtBeginning()
  }

  function kindColor(colorKey) {
    return root.palette[colorKey] || root.dim
  }

  function select(delta) {
    if (fileModel.count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + fileModel.count) % fileModel.count
    fileList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function openPath(path) {
    root.dismiss()
    Quickshell.execDetached(["xdg-open", path])
  }

  function copyIndex(index) {
    if (index < 0 || index >= fileModel.count) return
    var file = fileModel.get(index)
    root.dismiss()
    copier.uri = Files.fileUri(file.path)
    copier.running = true
    Quickshell.execDetached(["notify-send", "Downloads", "Copied to clipboard"])
  }

  // The URI goes to wl-copy over stdin, never argv, so other local users
  // can't read the filename from the process list. Closing stdin ends input.
  Process {
    id: copier
    property string uri: ""
    command: ["wl-copy", "--type", "text/uri-list"]
    stdinEnabled: true
    onStarted: {
      write(uri + "\n")
      uri = ""
      stdinEnabled = false
    }
    onExited: stdinEnabled = true
  }

  ListModel { id: fileModel }

  // First line is the Downloads folder, then one `mtime\tsize\tpath` line per
  // file. Partial browser downloads and hidden files are skipped.
  Process {
    id: lister
    command: ["bash", "-c",
      "dir=$(xdg-user-dir DOWNLOAD 2>/dev/null); dir=${dir:-$HOME/Downloads}; printf '%s\\n' \"$dir\"; " +
      "find \"$dir\" -maxdepth 1 -type f ! -name '.*' ! -name '*.part' ! -name '*.crdownload' ! -name '*.tmp' -printf '%T@\\t%s\\t%p\\n' 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: root.loadFiles(text)
    }
  }

  FileView {
    id: colorsFile
    path: Commons.Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.palette = Files.parseColors(text())
  }

  PanelWindow {
    id: panel
    visible: root.opened
    color: "transparent"
    implicitWidth: root.cardWidth
    implicitHeight: card.implicitHeight
    WlrLayershell.namespace: "kirklandgee-downloads"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    BorderSurface {
      id: card
      width: root.cardWidth
      implicitHeight: contentTopInset + contentBottomInset + column.implicitHeight
      height: implicitHeight
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: 0

      // Fade while dragging so the drop target underneath stays visible.
      opacity: root.dragging ? 0.35 : 1
      Behavior on opacity { NumberAnimation { duration: 120 } }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (fileModel.count > 0) root.openPath(fileModel.get(root.selectedIndex).path)
            event.accepted = true
          } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            root.copyIndex(root.selectedIndex)
            event.accepted = true
          }
        }
      }

      Column {
        id: column
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // Header: folder glyph, title, count, open-folder button.
        Item {
          width: parent.width
          height: root.headerHeight

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.panelPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xl

            Text {
              text: "\u{f024d}"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "Downloads"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.xxl
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            Text {
              textFormat: Text.PlainText
              text: fileModel.count + " recent"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              width: Style.space(28)
              height: Style.space(28)
              radius: root.cornerRadius
              color: folderMouse.containsMouse ? Util.alpha(root.accent, 0.14) : "transparent"
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.centerIn: parent
                text: "\u{f0770}"
                color: folderMouse.containsMouse ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
              }

              MouseArea {
                id: folderMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.downloadsDir) root.openPath(root.downloadsDir)
              }
            }
          }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: Util.alpha(root.foreground, 0.1) }

        Item {
          width: parent.width
          height: root.listHeight

          ListView {
            id: fileList
            anchors.fill: parent
            anchors.topMargin: Style.spacing.md
            anchors.bottomMargin: Style.spacing.md
            model: fileModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: !root.dragging

            delegate: Item {
              id: row
              required property int index
              required property string path
              required property string name
              required property string kind
              required property string glyph
              required property string colorKey
              required property real mtime
              required property real size

              readonly property bool selected: index === root.selectedIndex

              width: fileList.width
              height: root.rowHeight

              Rectangle {
                anchors.fill: parent
                color: row.selected ? root.selectedBackground : "transparent"
              }

              Rectangle {
                width: Style.space(3)
                height: parent.height
                color: root.accent
                visible: row.selected
              }

              Row {
                id: rowContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.spacing.panelPadding
                anchors.rightMargin: Style.spacing.panelPadding
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxl

                Item {
                  id: iconSlot
                  width: root.iconSize
                  height: root.iconSize
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    anchors.centerIn: parent
                    visible: thumb.status !== Image.Ready
                    text: row.glyph
                    color: root.kindColor(row.colorKey)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.displayLarge
                  }

                  Image {
                    id: thumb
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: row.kind === "image" ? Files.fileUri(row.path) : ""
                    sourceSize.width: root.iconSize * 2
                    sourceSize.height: root.iconSize * 2
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                  }
                }

                Column {
                  width: rowContent.width - iconSlot.width - rowContent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xs

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.name
                    color: row.selected ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideMiddle
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: Files.humanSize(row.size) + "  ·  " + Files.humanAge(row.mtime)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              // Invisible stand-in that carries the file out of the shell as a
              // real Wayland drag (text/uri-list), so any app can take the drop.
              Item {
                id: dragProxy
                width: iconSlot.width
                height: iconSlot.height
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: ({ "text/uri-list": Files.fileUri(row.path) })
                Drag.active: dragMouse.drag.active
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2
                Drag.onActiveChanged: root.dragging = Drag.active
                Drag.onDragFinished: function(dropAction) {
                  root.dragging = false
                  dragProxy.x = 0
                  dragProxy.y = 0
                  if (dropAction !== Qt.IgnoreAction) root.dismiss()
                }
              }

              MouseArea {
                id: dragMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                drag.target: dragProxy
                onContainsMouseChanged: if (containsMouse && !root.dragging) root.selectedIndex = row.index
                onPressed: iconSlot.grabToImage(function(result) { dragProxy.Drag.imageSource = result.url })
                onClicked: root.openPath(row.path)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: fileModel.count === 0
            textFormat: Text.PlainText
            text: "Nothing here yet"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: Util.alpha(root.foreground, 0.1) }

        Item {
          width: parent.width
          height: root.footerHeight

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "drag to share  ·  ⏎ open  ·  ctrl+c copy  ·  esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
