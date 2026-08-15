import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root

  readonly property string systemScript:
    Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.moduleName + "/scripts/system-usage"

  property string cpuText: "--"
  property var cores: []
  property string ramUsed: "--"
  property string ramTotal: "--"
  property int ramPct: 0
  property string gpuText: "n/a"
  property var disks: []

  function parse(raw) {
    var lines = String(raw || "").split("\n")
    var cores = []
    var disks = []
    var cpu = "--"
    var ramUsed = "--"
    var ramTotal = "--"
    var ramPct = 0
    var gpu = "n/a"

    for (var i = 0; i < lines.length; i++) {
      var line = String(lines[i]).trim()
      if (line === "") continue
      var parts = line.split(/\s+/)
      var key = parts[0]

      if (key === "cpu" && parts.length > 1) {
        cpu = parts[1] + "%"
      } else if (key === "core" && parts.length > 2) {
        var pct = parseFloat(parts[2])
        if (isFinite(pct)) cores.push({ core: parseInt(parts[1], 10), percent: Math.max(0, Math.min(100, Math.round(pct))) })
      } else if (key === "ram" && parts.length > 3) {
        ramUsed = parts[1]
        ramTotal = parts[2]
        ramPct = Math.max(0, Math.min(100, Math.round(parseFloat(parts[3]) || 0)))
      } else if (key === "gpu" && parts.length > 1) {
        gpu = parts[1] === "n/a" ? "n/a" : Math.max(0, Math.min(100, Math.round(parseFloat(parts[1]) || 0))) + "%"
      } else if (key === "disk" && parts.length > 4) {
        var diskPct = Math.max(0, Math.min(100, Math.round(parseFloat(parts[4]) || 0)))
        disks.push({ mount: parts[1], used: parts[2], total: parts[3], percent: diskPct })
      }
    }

    root.cpuText = cpu
    root.cores = cores
    root.ramUsed = ramUsed
    root.ramTotal = ramTotal
    root.ramPct = ramPct
    root.gpuText = gpu
    root.disks = disks
  }

  function launch() {
    if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍛"
    onPressed: function(b) { root.launch() }
  }

  HoverHandler {
    id: buttonHover
    target: button
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    triggerMode: "hover"
    open: buttonHover.hovered || popup.containsMouse
    contentWidth: popup.fittedContentWidth(Style.space(260))
    contentHeight: popup.fittedContentHeight(panel.implicitHeight, Style.space(480))

    Column {
      id: panel
      width: parent.width
      spacing: Style.spacing.md

      Item {
        width: parent.width
        implicitHeight: Math.max(cpuIcon.implicitHeight, cpuTitle.implicitHeight, cpuOverall.implicitHeight)

        Text {
          id: cpuIcon
          text: "󰍛"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: cpuTitle
          text: "CPU"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          anchors.left: cpuIcon.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: cpuOverall
          text: root.cpuText
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Grid {
        id: coresGrid
        width: parent.width
        columns: 2
        columnSpacing: Style.spacing.md
        rowSpacing: Style.spacing.sm

        Repeater {
          model: root.cores

          Row {
            required property var modelData

            width: (coresGrid.width - coresGrid.columnSpacing) / 2
            spacing: Style.space(6)

            Text {
              text: "C" + modelData.core
              color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.3)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              width: Style.space(20)
              anchors.verticalCenter: parent.verticalCenter
            }

            Item {
              width: parent.width - Style.space(20) - Style.space(34) - Style.space(12)
              height: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, height / 2) : 0
                color: Util.alpha(root.bar ? root.bar.foreground : Color.foreground, 0.18)
              }

              Rectangle {
                width: parent.width * modelData.percent / 100
                height: parent.height
                radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, height / 2) : 0
                color: Util.alpha(Color.accent, 0.9)
              }
            }

            Text {
              text: modelData.percent + "%"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              width: Style.space(34)
              horizontalAlignment: Text.AlignRight
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }

      PanelSeparator {
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }

      StatRow {
        icon: "󰓅"
        label: "RAM"
        value: root.ramPct + "%"
        percent: root.ramPct
        caption: root.ramUsed + " / " + root.ramTotal + " GiB"
      }

      PanelSeparator {
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }

      StatRow {
        icon: "󰢮"
        label: "GPU"
        value: root.gpuText
        percent: root.gpuText === "n/a" ? -1 : parseInt(root.gpuText, 10)
        caption: root.gpuText === "n/a" ? "GPU stats unavailable" : ""
      }

      PanelSeparator {
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }

      Item {
        width: parent.width
        implicitHeight: Math.max(diskIcon.implicitHeight, diskTitle.implicitHeight)

        Text {
          id: diskIcon
          text: "󰋊"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: diskTitle
          text: "Storage"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          anchors.left: diskIcon.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Column {
        id: disksColumn
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
          model: root.disks

          StatRow {
            required property var modelData

            label: modelData.mount
            value: modelData.percent + "%"
            percent: modelData.percent
            caption: modelData.used + " / " + modelData.total + " GiB"
          }
        }
      }
    }
  }

  component StatRow: Item {
    id: statRow

    required property string label
    required property string value
    required property int percent
    property string caption: ""
    property string icon: ""

    width: parent.width

    readonly property real headerHeight: Math.max(
      statIcon.implicitHeight,
      Math.max(statLabel.implicitHeight, statValue.implicitHeight))

    readonly property real barHeight: Style.space(5)
    readonly property real gap: Style.space(3)
    readonly property real barBlock: percent >= 0 ? gap + barHeight : 0

    implicitHeight: headerHeight
      + barBlock
      + (captionText.visible ? gap + captionText.implicitHeight : 0)

    Item {
      id: headerRow
      width: parent.width
      height: statRow.headerHeight

      Text {
        id: statIcon
        visible: statRow.icon !== ""
        text: statRow.icon
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: statLabel
        text: statRow.label
        color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.3)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.left: statIcon.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: statValue
        text: statRow.value
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Rectangle {
      id: statTrack
      visible: statRow.percent >= 0
      y: headerRow.height + statRow.gap
      width: parent.width
      height: statRow.barHeight
      radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, height / 2) : 0
      color: Util.alpha(root.bar ? root.bar.foreground : Color.foreground, 0.18)
    }

    Rectangle {
      id: statFill
      visible: statRow.percent >= 0
      y: headerRow.height + statRow.gap
      width: parent.width * statRow.percent / 100
      height: statRow.barHeight
      radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, height / 2) : 0
      color: Util.alpha(Color.accent, 0.9)
    }

    Text {
      id: captionText
      visible: statRow.caption !== ""
      y: headerRow.height + statRow.barBlock + statRow.gap
      width: parent.width
      text: statRow.caption
      color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.45)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Process {
    id: systemProc
    command: [root.systemScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!systemProc.running) systemProc.running = true
  }
}
