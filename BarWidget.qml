import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property int upCount: mainInstance?.upCount ?? 0
  readonly property int totalCount: mainInstance?.totalCount ?? 0
  readonly property bool anyDown: mainInstance?.anyDown ?? false
  readonly property bool isChecking: mainInstance?.isChecking ?? false
  readonly property bool showCountBadge: mainInstance?.showCountBadge ?? true
  readonly property bool allUp: totalCount > 0 && upCount === totalCount
  readonly property bool noData: totalCount === 0 || upCount === 0 && !anyDown

  readonly property real contentWidth: showCountBadge
    ? (contentRow.implicitWidth + Style.marginM * 2)
    : Style.capsuleHeight
  readonly property real contentHeight: Style.capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight

  Rectangle {
    id: visualCapsule
    anchors.centerIn: parent
    width: root.contentWidth
    height: root.contentHeight
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
    radius: Style.radiusL

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.marginXS

      // Server icon with status dot overlay
      Item {
        Layout.preferredWidth: serverIcon.implicitWidth
        Layout.preferredHeight: serverIcon.implicitHeight

        NIcon {
          id: serverIcon
          icon: "server"
          pointSize: Style.fontSizeL
          applyUiScale: false
          color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
        }

        // Status dot in corner
        Rectangle {
          width: 7
          height: 7
          radius: 4
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: -1
          anchors.bottomMargin: -1
          color: root.noData ? Color.mOutline
                 : root.allUp ? "#22C55E"
                 : root.anyDown ? "#EF4444"
                 : "#F59E0B"
          border.color: Style.capsuleColor
          border.width: 1

          SequentialAnimation on opacity {
            running: root.anyDown
            loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 700 }
            NumberAnimation { to: 1.0; duration: 700 }
          }
        }
      }

      // Count badge
      NText {
        visible: root.showCountBadge && root.totalCount > 0
        text: root.upCount + "/" + root.totalCount
        pointSize: Style.fontSizeXS
        color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
        font.family: Settings.data.ui.fontFixed
        Layout.leftMargin: Style.marginXS
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu
    model: [
      {
        "label": "Atualizar agora",
        "action": "refresh",
        "icon": "refresh"
      },
      {
        "label": "Configurações",
        "action": "widget-settings",
        "icon": "settings"
      }
    ]
    onTriggered: action => {
      contextMenu.close()
      PanelService.closeContextMenu(screen)
      if (action === "refresh" && mainInstance) {
        mainInstance.refresh()
      } else if (action === "widget-settings") {
        BarService.openPluginSettings(screen, pluginApi.manifest)
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: (mouse) => {
      if (mouse.button === Qt.LeftButton) {
        if (pluginApi) pluginApi.openPanel(root.screen, root)
      } else {
        PanelService.showContextMenu(contextMenu, root, screen)
      }
    }
  }
}
