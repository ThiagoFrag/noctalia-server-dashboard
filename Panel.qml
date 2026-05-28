import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property var services: mainInstance?.services ?? []
  readonly property int upCount: mainInstance?.upCount ?? 0
  readonly property int totalCount: mainInstance?.totalCount ?? 0
  readonly property bool isChecking: mainInstance?.isChecking ?? false
  readonly property string discoveryState: mainInstance?.discoveryState ?? "idle"
  readonly property string discoveryError: mainInstance?.discoveryError ?? ""
  readonly property double lastDiscoveryAt: mainInstance?.lastDiscoveryAt ?? 0
  readonly property var allServers: mainInstance?.servers ?? []
  readonly property string activeServerName: mainInstance?.activeServerName ?? "Sem servidor"
  readonly property string activeServerId: mainInstance?.activeServerId ?? ""
  readonly property bool multipleServers: allServers.length > 1

  property bool panelReady: true

  readonly property int tileSize: 110
  readonly property int tileSpacing: Style.marginS
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/noctalia/plugins/server-dashboard"

  readonly property bool hasServices: services.length > 0
  readonly property bool showErrorScreen: !hasServices && discoveryState === "error"
  readonly property bool showLoadingScreen: !hasServices && discoveryState === "loading"

  function timeAgo(ts) {
    if (!ts) return "nunca"
    var s = Math.round((Date.now() - ts) / 1000)
    if (s < 5) return "agora"
    if (s < 60) return s + "s atrás"
    if (s < 3600) return Math.floor(s / 60) + "min atrás"
    return Math.floor(s / 3600) + "h atrás"
  }

  implicitWidth: 520
  implicitHeight: 1100

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"
    visible: panelReady

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      // ─── Header ──────────────────────────────────────────────────────────
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: 64

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.marginL
          anchors.rightMargin: Style.marginS
          spacing: Style.marginM

          Rectangle {
            width: 42
            height: 42
            radius: Style.radiusM
            color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18)

            NIcon {
              anchors.centerIn: parent
              icon: "server"
              pointSize: Style.fontSizeXL
              color: Color.mPrimary
            }
          }

          Item {
            id: headerInfoColumn
            Layout.fillWidth: true
            implicitHeight: headerCol.implicitHeight

            ColumnLayout {
              id: headerCol
              anchors.fill: parent
              spacing: 1

              RowLayout {
                spacing: 4
                Layout.fillWidth: true

                NText {
                  text: root.activeServerName
                  pointSize: Style.fontSizeL
                  font.weight: Font.DemiBold
                  color: serverSwitcherArea.containsMouse && root.multipleServers
                    ? Color.mPrimary : Color.mOnSurface
                  elide: Text.ElideRight
                  Behavior on color { ColorAnimation { duration: 120 } }
                }

                NIcon {
                  visible: root.multipleServers
                  icon: "chevron-down"
                  pointSize: Style.fontSizeS
                  color: serverSwitcherArea.containsMouse ? Color.mPrimary : Color.mOnSurfaceVariant
                }

                Item { Layout.fillWidth: true }
              }

              RowLayout {
                spacing: Style.marginS

                Rectangle {
                  width: 7; height: 7; radius: 4
                  Layout.alignment: Qt.AlignVCenter
                  color: root.discoveryState === "error" ? "#EF4444"
                         : root.totalCount === 0 ? Color.mOutline
                         : root.upCount === root.totalCount ? "#22C55E"
                         : root.upCount === 0 ? "#EF4444" : "#F59E0B"
                }

                NText {
                  text: {
                    if (root.discoveryState === "error") return "erro no discovery"
                    if (root.totalCount === 0) return "nenhum serviço"
                    return root.upCount + " de " + root.totalCount + " online"
                  }
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  visible: root.lastDiscoveryAt > 0
                  text: "• descoberto " + root.timeAgo(root.lastDiscoveryAt)
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                  opacity: 0.6
                }
              }
            }

            MouseArea {
              id: serverSwitcherArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.multipleServers ? Qt.PointingHandCursor : Qt.ArrowCursor
              enabled: root.multipleServers
              onClicked: serverSwitcherMenu.popup()
            }

            Menu {
              id: serverSwitcherMenu
              Repeater {
                model: root.allServers
                MenuItem {
                  required property var modelData
                  text: (modelData.id === root.activeServerId ? "✓  " : "    ") + modelData.name
                  onTriggered: if (mainInstance) mainInstance.switchServer(modelData.id)
                }
              }
            }
          }

          NIconButton {
            icon: "search"
            tooltipText: "Descobrir do servidor agora"
            enabled: root.discoveryState !== "loading"
            opacity: root.discoveryState === "loading" ? 0.45 : 1.0
            onClicked: if (mainInstance) mainInstance.runDiscovery()
          }

          NIconButton {
            icon: "refresh"
            tooltipText: "Verificar status agora"
            enabled: !root.isChecking && root.hasServices
            opacity: root.isChecking ? 0.45 : 1.0
            onClicked: if (mainInstance) mainInstance.refresh()
            RotationAnimation on rotation {
              running: root.isChecking
              loops: Animation.Infinite
              from: 0; to: 360
              duration: 1000
            }
          }

          NIconButton {
            icon: "settings"
            tooltipText: "Configurações"
            onClicked: {
              if (pluginApi) pluginApi.withCurrentScreen(function(screen) {
                BarService.openPluginSettings(screen, pluginApi.manifest)
              })
            }
          }
        }
      }

      // ─── Body ────────────────────────────────────────────────────────────
      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // ▶ ERROR STATE
        ColumnLayout {
          anchors.centerIn: parent
          width: parent.width - Style.marginXL * 2
          visible: root.showErrorScreen
          spacing: Style.marginM

          NIcon {
            icon: "alert-circle"
            pointSize: 48
            color: "#EF4444"
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: "Não foi possível descobrir serviços"
            pointSize: Style.fontSizeL
            font.weight: Font.Medium
            color: Color.mOnSurface
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
          }

          NText {
            text: root.discoveryError
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
          }

          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Style.marginM
            spacing: Style.marginS

            NButton {
              text: "Tentar de novo"
              icon: "refresh"
              onClicked: if (mainInstance) mainInstance.runDiscovery()
            }

            NButton {
              text: "Configurações"
              icon: "settings"
              outlined: true
              onClicked: if (pluginApi) pluginApi.withCurrentScreen(function(screen) {
                BarService.openPluginSettings(screen, pluginApi.manifest)
              })
            }
          }
        }

        // ▶ LOADING STATE
        ColumnLayout {
          anchors.centerIn: parent
          visible: root.showLoadingScreen
          spacing: Style.marginM

          NBusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
          }

          NText {
            text: "Conectando ao servidor..."
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
          }
        }

        // ▶ NORMAL: grid
        ScrollView {
          anchors.fill: parent
          anchors.margins: Style.marginM
          visible: root.hasServices && !root.showErrorScreen
          contentWidth: availableWidth
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

          ColumnLayout {
            width: parent.width
            spacing: Style.marginL

            Repeater {
              model: mainInstance ? mainInstance.uniqueCategories() : []

              ColumnLayout {
                id: categoryGroup
                Layout.fillWidth: true
                spacing: Style.marginS

                required property string modelData
                readonly property var categoryServices: mainInstance ? mainInstance.servicesIn(modelData) : []
                readonly property int categoryUp: {
                  var n = 0
                  for (var i = 0; i < categoryServices.length; i++) {
                    if (mainInstance && mainInstance.statusOf(categoryServices[i].url) === "up") n++
                  }
                  return n
                }

                // Category header
                RowLayout {
                  Layout.fillWidth: true
                  Layout.leftMargin: 2
                  Layout.bottomMargin: 2
                  spacing: Style.marginS

                  NText {
                    text: categoryGroup.modelData.toUpperCase()
                    pointSize: Style.fontSizeXS
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                    color: Color.mOnSurfaceVariant
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Color.mOutline
                    opacity: 0.3
                  }

                  NText {
                    text: categoryGroup.categoryUp + "/" + categoryGroup.categoryServices.length
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                    opacity: 0.7
                    font.family: Settings.data.ui.fontFixed
                  }
                }

                // Tiles flow
                Flow {
                  Layout.fillWidth: true
                  spacing: root.tileSpacing

                  Repeater {
                    model: categoryGroup.categoryServices

                    Rectangle {
                      id: tile
                      required property var modelData
                      width: root.tileSize
                      height: root.tileSize
                      radius: Style.radiusM
                      clip: true

                      readonly property string status: mainInstance ? mainInstance.statusOf(modelData.url) : "unknown"
                      readonly property bool isUp: status === "up"
                      readonly property bool isDown: status === "down"
                      readonly property color brandColor: modelData.color || Color.mPrimary

                      color: tileMouse.containsMouse
                        ? Qt.rgba(brandColor.r, brandColor.g, brandColor.b, 0.18)
                        : Qt.rgba(0, 0, 0, 0.28)
                      Behavior on color { ColorAnimation { duration: 150 } }

                      border.width: 1
                      border.color: tileMouse.containsMouse
                        ? Qt.rgba(brandColor.r, brandColor.g, brandColor.b, 0.6)
                        : Qt.rgba(255, 255, 255, 0.06)
                      Behavior on border.color { ColorAnimation { duration: 150 } }

                      opacity: tile.isDown ? 0.6 : 1.0
                      Behavior on opacity { NumberAnimation { duration: 200 } }

                      // Left accent bar
                      Rectangle {
                        width: 4
                        height: parent.height
                        anchors.left: parent.left
                        color: tile.brandColor
                        radius: 2
                      }

                      // Status dot
                      Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 7
                        color: tile.isUp ? "#22C55E"
                               : tile.isDown ? "#EF4444"
                               : "#9CA3AF"

                        SequentialAnimation on opacity {
                          running: tile.isDown
                          loops: Animation.Infinite
                          NumberAnimation { to: 0.35; duration: 700 }
                          NumberAnimation { to: 1.0; duration: 700 }
                        }
                      }

                      ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        anchors.topMargin: 10
                        anchors.bottomMargin: 8
                        spacing: 4

                        Item {
                          Layout.fillWidth: true
                          Layout.fillHeight: true
                          Layout.alignment: Qt.AlignHCenter

                          readonly property bool hasIcon: tile.modelData.iconFile !== undefined && tile.modelData.iconFile !== ""

                          Image {
                            id: logoImage
                            anchors.centerIn: parent
                            visible: parent.hasIcon && logoImage.status !== Image.Error
                            source: parent.hasIcon
                              ? "file://" + root.pluginDir + "/" + tile.modelData.iconFile
                              : ""
                            sourceSize.width: 64
                            sourceSize.height: 64
                            width: 56
                            height: 56
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            asynchronous: true
                          }

                          Text {
                            anchors.centerIn: parent
                            visible: !logoImage.visible
                            text: tile.modelData.icon || tile.modelData.name.charAt(0).toUpperCase()
                            color: tile.brandColor
                            font.pixelSize: 36
                            font.weight: Font.Bold
                          }
                        }

                        Text {
                          text: tile.modelData.name
                          color: Color.mOnSurface
                          font.pixelSize: 10
                          font.weight: Font.Medium
                          Layout.alignment: Qt.AlignHCenter
                          Layout.maximumWidth: root.tileSize - 24
                          elide: Text.ElideRight
                          horizontalAlignment: Text.AlignHCenter
                        }
                      }

                      MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (mainInstance) mainInstance.openService(tile.modelData.url)
                      }

                      ToolTip.visible: tileMouse.containsMouse
                      ToolTip.delay: 700
                      ToolTip.text: tile.modelData.name + " (" + tile.modelData.rawName + ")\n"
                                    + tile.modelData.url + "\n"
                                    + (tile.isUp ? "● Online" : tile.isDown ? "● Offline" : "○ Verificando...")
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
