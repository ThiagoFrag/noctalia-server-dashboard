import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  readonly property var mainInstance: pluginApi?.mainInstance

  // ─── Live state ──────────────────────────────────────────────────────────
  readonly property var servers: mainInstance?.servers ?? []
  readonly property string activeServerId: mainInstance?.activeServerId ?? ""
  readonly property var tailscalePeers: mainInstance?.tailscalePeers ?? []
  readonly property bool tailscaleListing: mainInstance?.tailscaleListing ?? false
  readonly property var userDetecting: mainInstance?.userDetecting ?? ({})

  function isDetectingFor(id) { return userDetecting[id] === true }

  // ─── Editable config (sync from settings) ────────────────────────────────
  property int editRefreshInterval:
    pluginApi?.pluginSettings?.refreshInterval ||
    pluginApi?.manifest?.metadata?.defaultSettings?.refreshInterval ||
    30000

  property int editDiscoveryInterval:
    pluginApi?.pluginSettings?.discoveryInterval ||
    pluginApi?.manifest?.metadata?.defaultSettings?.discoveryInterval ||
    300000

  property bool editShowCountBadge:
    pluginApi?.pluginSettings?.showCountBadge ??
    pluginApi?.manifest?.metadata?.defaultSettings?.showCountBadge ??
    true

  property string editDefaultSshUser:
    pluginApi?.pluginSettings?.defaultSshUser ||
    pluginApi?.manifest?.metadata?.defaultSettings?.defaultSshUser ||
    "th"

  // ─── Add manual form ─────────────────────────────────────────────────────
  property bool showAddForm: false
  property string newId: ""
  property string newName: ""
  property string newHost: ""
  property string newUser: ""
  property int newPort: 22

  property bool showTailscaleList: false

  // ─── Edit inline ─────────────────────────────────────────────────────────
  property string editingServerId: ""
  property string editName: ""
  property string editHost: ""
  property string editUser: ""
  property int editPort: 22

  function startEditing(server) {
    editingServerId = server.id
    editName = server.name || ""
    editHost = server.host || ""
    editUser = server.user || editDefaultSshUser
    editPort = server.port || 22
  }
  function cancelEditing() {
    editingServerId = ""
  }
  function commitEditing() {
    if (!mainInstance || !editingServerId) return
    mainInstance.editServer(editingServerId, {
      name: editName.trim() || editingServerId,
      host: editHost.trim(),
      user: editUser.trim() || editDefaultSshUser,
      port: editPort
    })
    editingServerId = ""
  }

  spacing: Style.marginL

  // ────────────────────────────────────────────────────────────────────────
  // GERAL
  // ────────────────────────────────────────────────────────────────────────
  NLabel {
    label: "Geral"
    description: "Frequência das verificações"
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    ColumnLayout {
      Layout.fillWidth: true
      NLabel { label: "Intervalo de health check"; description: "Frequência (ms) do curl. Padrão 30000" }
    }
    NSpinBox {
      from: 5000; to: 600000; stepSize: 5000
      value: root.editRefreshInterval
      onValueChanged: root.editRefreshInterval = value
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    ColumnLayout {
      Layout.fillWidth: true
      NLabel { label: "Intervalo de discovery"; description: "Frequência (ms) do ssh+docker ps. Padrão 300000 (5min)" }
    }
    NSpinBox {
      from: 60000; to: 3600000; stepSize: 60000
      value: root.editDiscoveryInterval
      onValueChanged: root.editDiscoveryInterval = value
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    ColumnLayout {
      Layout.fillWidth: true
      NLabel { label: "Badge na barra"; description: "Mostra contador 'X/Y' ao lado do ícone" }
    }
    NCheckbox {
      checked: root.editShowCountBadge
      onCheckedChanged: root.editShowCountBadge = checked
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: "Usuário SSH padrão"
    description: "Usado quando adicionar novo servidor"
    text: root.editDefaultSshUser
    onTextChanged: root.editDefaultSshUser = text
  }

  NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginS }

  // ────────────────────────────────────────────────────────────────────────
  // SERVIDORES
  // ────────────────────────────────────────────────────────────────────────
  NLabel {
    label: "Servidores"
    description: "Adicione múltiplos servidores e troque entre eles no painel"
  }

  // Lista de servers
  Repeater {
    model: root.servers

    ColumnLayout {
      required property var modelData
      readonly property bool isActive: modelData.id === root.activeServerId
      readonly property bool isEditing: modelData.id === root.editingServerId

      Layout.fillWidth: true
      spacing: 0

      // Server row
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 56
        radius: Style.radiusM
        color: parent.isActive ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.10)
                               : Qt.rgba(0, 0, 0, 0.18)
        border.color: parent.isActive ? Color.mPrimary : Qt.rgba(255, 255, 255, 0.06)
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.marginM
          anchors.rightMargin: Style.marginS
          spacing: Style.marginM

          Rectangle {
            width: 8; height: 8; radius: 4
            color: parent.parent.parent.isActive ? Color.mPrimary : Color.mOutline
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            NText {
              text: modelData.name + (parent.parent.parent.parent.isActive ? "  •  ativo" : "")
              pointSize: Style.fontSizeM
              font.weight: Font.Medium
              color: Color.mOnSurface
            }

            NText {
              text: (modelData.user || "th") + "@" + modelData.host + ":" + (modelData.port || 22)
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              font.family: Settings.data.ui.fontFixed
            }
          }

          NButton {
            visible: !parent.parent.parent.isActive
            text: "Ativar"
            outlined: true
            onClicked: if (mainInstance) mainInstance.switchServer(modelData.id)
          }

          NIconButton {
            icon: parent.parent.parent.isEditing ? "x" : "settings"
            tooltipText: parent.parent.parent.isEditing ? "Cancelar" : "Editar"
            onClicked: {
              if (root.editingServerId === modelData.id) root.cancelEditing()
              else root.startEditing(modelData)
            }
          }

          NIconButton {
            icon: "trash"
            tooltipText: "Remover servidor"
            enabled: root.servers.length > 1
            onClicked: if (mainInstance) mainInstance.removeServer(modelData.id)
          }
        }
      }

      // Inline edit form
      Rectangle {
        visible: parent.isEditing
        Layout.fillWidth: true
        Layout.topMargin: 2
        Layout.preferredHeight: visible ? editCol.implicitHeight + Style.marginL * 2 : 0
        radius: Style.radiusM
        color: Qt.rgba(0, 0, 0, 0.25)
        border.color: Color.mPrimary
        border.width: 1

        ColumnLayout {
          id: editCol
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginS

          NLabel { label: "Editando " + modelData.id; description: "ID não pode ser alterado" }

          NTextInput {
            Layout.fillWidth: true
            label: "Nome"
            text: root.editName
            onTextChanged: root.editName = text
          }

          NTextInput {
            Layout.fillWidth: true
            label: "Host"
            text: root.editHost
            onTextChanged: root.editHost = text
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            NTextInput {
              Layout.fillWidth: true
              label: "Usuário SSH"
              text: root.editUser
              onTextChanged: root.editUser = text
            }
            ColumnLayout {
              NLabel { label: "Porta"; description: "" }
              NSpinBox {
                from: 1; to: 65535
                value: root.editPort
                onValueChanged: root.editPort = value
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.marginS
            Item { Layout.fillWidth: true }
            NButton {
              text: "Cancelar"
              outlined: true
              onClicked: root.cancelEditing()
            }
            NButton {
              text: "Salvar e re-descobrir"
              enabled: root.editHost.trim() !== "" && root.editUser.trim() !== ""
              onClicked: root.commitEditing()
            }
          }
        }
      }
    }
  }

  // Botões de adicionar
  RowLayout {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXS
    spacing: Style.marginS

    NButton {
      text: root.showAddForm ? "Cancelar" : "+ Adicionar manual"
      outlined: true
      onClicked: {
        root.showAddForm = !root.showAddForm
        if (root.showAddForm) root.showTailscaleList = false
      }
    }

    NButton {
      text: root.showTailscaleList ? "Fechar lista" : "+ Importar do Tailscale"
      outlined: true
      onClicked: {
        root.showTailscaleList = !root.showTailscaleList
        if (root.showTailscaleList) {
          root.showAddForm = false
          if (mainInstance) mainInstance.listTailscalePeers()
        }
      }
    }
  }

  // Form adicionar manual
  Rectangle {
    visible: root.showAddForm
    Layout.fillWidth: true
    Layout.preferredHeight: addFormCol.implicitHeight + Style.marginL * 2
    radius: Style.radiusM
    color: Qt.rgba(0, 0, 0, 0.25)
    border.color: Qt.rgba(255, 255, 255, 0.06)
    border.width: 1

    ColumnLayout {
      id: addFormCol
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginS

      NLabel { label: "Novo servidor"; description: "Preencha os campos e clique Salvar" }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NTextInput {
          Layout.fillWidth: true
          label: "ID (interno)"
          placeholderText: "ex: meu-vps"
          text: root.newId
          onTextChanged: root.newId = text
        }
        NTextInput {
          Layout.fillWidth: true
          label: "Nome"
          placeholderText: "ex: Meu VPS"
          text: root.newName
          onTextChanged: root.newName = text
        }
      }

      NTextInput {
        Layout.fillWidth: true
        label: "Host (IP ou DNS)"
        placeholderText: "100.x.x.x ou meu-host.example.com"
        text: root.newHost
        onTextChanged: root.newHost = text
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NTextInput {
          Layout.fillWidth: true
          label: "Usuário SSH"
          placeholderText: root.editDefaultSshUser
          text: root.newUser
          onTextChanged: root.newUser = text
        }
        ColumnLayout {
          NLabel { label: "Porta"; description: "" }
          NSpinBox {
            from: 1; to: 65535
            value: root.newPort
            onValueChanged: root.newPort = value
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Item { Layout.fillWidth: true }
        NButton {
          text: "Salvar"
          enabled: root.newId !== "" && root.newHost !== ""
          onClicked: {
            if (!mainInstance) return
            mainInstance.addServer({
              id: root.newId.trim(),
              name: root.newName.trim() || root.newId.trim(),
              host: root.newHost.trim(),
              user: root.newUser.trim() || root.editDefaultSshUser,
              port: root.newPort
            })
            root.newId = ""; root.newName = ""; root.newHost = ""; root.newUser = ""; root.newPort = 22
            root.showAddForm = false
          }
        }
      }
    }
  }

  // Lista Tailscale
  Rectangle {
    visible: root.showTailscaleList
    Layout.fillWidth: true
    Layout.preferredHeight: tailscaleCol.implicitHeight + Style.marginL * 2
    radius: Style.radiusM
    color: Qt.rgba(0, 0, 0, 0.25)
    border.color: Qt.rgba(255, 255, 255, 0.06)
    border.width: 1

    ColumnLayout {
      id: tailscaleCol
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginS

      RowLayout {
        Layout.fillWidth: true
        NLabel {
          Layout.fillWidth: true
          label: "Peers no Tailscale"
          description: root.tailscaleListing
            ? "Consultando tailscale status..."
            : (root.tailscalePeers.length + " peers online encontrados")
        }
        NIconButton {
          icon: "refresh"
          tooltipText: "Atualizar lista"
          enabled: !root.tailscaleListing
          onClicked: if (mainInstance) mainInstance.listTailscalePeers()
        }
      }

      Repeater {
        model: root.tailscalePeers

        Rectangle {
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: 48
          radius: Style.radiusS
          color: Qt.rgba(255, 255, 255, 0.03)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.marginM
            anchors.rightMargin: Style.marginS
            spacing: Style.marginM

            NIcon {
              icon: "server"
              pointSize: Style.fontSizeL
              color: modelData.alreadyAdded ? Color.mOutline : Color.mPrimary
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              NText {
                text: modelData.name
                pointSize: Style.fontSizeS
                font.weight: Font.Medium
                color: Color.mOnSurface
              }
              NText {
                text: modelData.host + " · " + (modelData.os || "linux")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                font.family: Settings.data.ui.fontFixed
              }
            }

            NButton {
              text: modelData.alreadyAdded ? "Já adicionado"
                    : (root.isDetectingFor(modelData.id) ? "Detectando user..." : "+ Adicionar (auto)")
              outlined: true
              enabled: !modelData.alreadyAdded && !root.isDetectingFor(modelData.id)
              onClicked: {
                if (!mainInstance) return
                mainInstance.autoAddServer({
                  id: modelData.id,
                  name: modelData.name,
                  host: modelData.host,
                  port: 22
                })
                Qt.callLater(function() {
                  if (mainInstance) mainInstance.listTailscalePeers()
                })
              }
            }
          }
        }
      }

      NText {
        visible: !root.tailscaleListing && root.tailscalePeers.length === 0
        text: "Nenhum peer encontrado. Verifique se o Tailscale está conectado."
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
      }
    }
  }

  NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginS }

  // ────────────────────────────────────────────────────────────────────────
  // AVANÇADO
  // ────────────────────────────────────────────────────────────────────────
  NLabel {
    label: "Avançado"
    description: "Para editar overrides, categorias e ícones, edite o manifest.json"
  }

  NButton {
    text: "Abrir pasta do plugin"
    icon: "folder-open"
    outlined: true
    onClicked: Quickshell.execDetached([
      "xdg-open",
      Quickshell.env("HOME") + "/.config/noctalia/plugins/server-dashboard"
    ])
  }

  Item { Layout.fillHeight: true }

  // ────────────────────────────────────────────────────────────────────────
  // SAVE
  // ────────────────────────────────────────────────────────────────────────
  function saveSettings() {
    if (!pluginApi) return
    pluginApi.pluginSettings.refreshInterval = root.editRefreshInterval
    pluginApi.pluginSettings.discoveryInterval = root.editDiscoveryInterval
    pluginApi.pluginSettings.showCountBadge = root.editShowCountBadge
    pluginApi.pluginSettings.defaultSshUser = root.editDefaultSshUser
    pluginApi.saveSettings()
  }
}
