import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi: null

  // ─── Settings (reactive) ─────────────────────────────────────────────────
  property int settingsVersion: 0
  property var settingsWatcher: pluginApi?.pluginSettings
  onPluginApiChanged: { if (pluginApi) settingsVersion++ }
  onSettingsWatcherChanged: { if (settingsWatcher) settingsVersion++ }

  readonly property var servers: pluginApi?.pluginSettings?.servers
                                 ?? pluginApi?.manifest?.metadata?.defaultSettings?.servers
                                 ?? []
  readonly property string activeServerId: pluginApi?.pluginSettings?.activeServerId
                                           ?? pluginApi?.manifest?.metadata?.defaultSettings?.activeServerId
                                           ?? ""
  readonly property string defaultSshUser: pluginApi?.pluginSettings?.defaultSshUser
                                           ?? pluginApi?.manifest?.metadata?.defaultSettings?.defaultSshUser
                                           ?? "th"

  readonly property var activeServer: {
    for (var i = 0; i < servers.length; i++) {
      if (servers[i].id === activeServerId) return servers[i]
    }
    return servers.length > 0 ? servers[0] : null
  }
  readonly property string sshHost: activeServer?.host ?? ""
  readonly property string sshUser: activeServer?.user ?? defaultSshUser
  readonly property int sshPort: activeServer?.port ?? 22
  readonly property string activeServerName: activeServer?.name ?? (activeServer?.id || "Sem servidor")

  readonly property int discoveryInterval: pluginApi?.pluginSettings?.discoveryInterval ?? 300000
  readonly property int refreshInterval: pluginApi?.pluginSettings?.refreshInterval ?? 30000
  readonly property bool showCountBadge: pluginApi?.pluginSettings?.showCountBadge ?? true

  readonly property var overrides: pluginApi?.pluginSettings?.overrides
                                   ?? pluginApi?.manifest?.metadata?.defaultSettings?.overrides
                                   ?? ({})
  readonly property var categoryRules: pluginApi?.pluginSettings?.categoryRules
                                       ?? pluginApi?.manifest?.metadata?.defaultSettings?.categoryRules
                                       ?? []
  readonly property var iconMap: pluginApi?.pluginSettings?.iconMap
                                 ?? pluginApi?.manifest?.metadata?.defaultSettings?.iconMap
                                 ?? ({})
  readonly property var categoryColors: pluginApi?.pluginSettings?.categoryColors
                                        ?? pluginApi?.manifest?.metadata?.defaultSettings?.categoryColors
                                        ?? ({})

  // ─── Paths ───────────────────────────────────────────────────────────────
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/noctalia/plugins/server-dashboard"
  readonly property string cacheFile: pluginDir + "/discovery-cache.json"

  // ─── Discovery state ─────────────────────────────────────────────────────
  // cacheByServer: { [serverId]: { generatedAt, services: [] } }
  property var cacheByServer: ({})
  property string discoveryState: "idle"
  property string discoveryError: ""

  // Tailscale peer listing
  property var tailscalePeers: []
  property bool tailscaleListing: false

  // User detection
  property var userDetecting: ({})    // { serverId: true } while detection running
  property var _recoveryAttempted: ({})  // prevents infinite recovery loops

  // ─── Health state ────────────────────────────────────────────────────────
  property var statuses: ({})
  property bool isChecking: false
  property double lastCheckAt: 0

  // ─── Derived ─────────────────────────────────────────────────────────────
  readonly property var services: cacheByServer[activeServerId]?.services ?? []
  readonly property double lastDiscoveryAt: cacheByServer[activeServerId]?.generatedAt ?? 0
  readonly property int totalCount: services.length
  readonly property int upCount: {
    var n = 0
    for (var i = 0; i < services.length; i++) {
      if (statuses[services[i].url] === "up") n++
    }
    return n
  }
  readonly property bool anyDown: {
    for (var i = 0; i < services.length; i++) {
      if (statuses[services[i].url] === "down") return true
    }
    return false
  }

  function uniqueCategories() {
    var seen = {}, out = []
    for (var i = 0; i < services.length; i++) {
      var c = services[i].category || "Outros"
      if (!seen[c]) { seen[c] = true; out.push(c) }
    }
    return out
  }
  function servicesIn(category) {
    return services.filter(function(s) { return (s.category || "Outros") === category })
  }
  function statusOf(url) { return statuses[url] || "unknown" }
  function openService(url) { if (url) Qt.openUrlExternally(url) }

  // ─── Parser helpers ──────────────────────────────────────────────────────
  function _displayName(raw) {
    var name = String(raw || "").replace(/[-_](\d+|server|client|app|service|main|web|api)$/i, "")
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  function _resolveCategory(containerName) {
    var lc = containerName.toLowerCase()
    for (var i = 0; i < categoryRules.length; i++) {
      try {
        if (new RegExp(categoryRules[i].match, "i").test(lc)) return categoryRules[i].category
      } catch (e) {}
    }
    return "Outros"
  }

  function _resolveIconFile(containerName) {
    var lc = containerName.toLowerCase()
    if (iconMap[lc]) return iconMap[lc]
    for (var slug in iconMap) {
      if (lc.indexOf(slug) !== -1) return iconMap[slug]
    }
    return ""
  }

  function _resolveProtocol(port) {
    return (port === "443" || port === "8443") ? "https" : "http"
  }

  function _parseDockerOutput(stdout, hostForUrl) {
    var lines = String(stdout || "").trim().split("\n")
    var results = []

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue

      var parts = line.split("|")
      if (parts.length < 2) continue

      var containerName = parts[0].trim()
      var portsStr = parts[1] || ""
      var image = (parts[2] || "").trim()

      var ovr = overrides[containerName] || {}
      if (ovr.hidden === true) continue

      var portRegex = /(\d+\.\d+\.\d+\.\d+):(\d+)->\d+\/tcp/g
      var port = ""
      var pm
      while ((pm = portRegex.exec(portsStr)) !== null) {
        if (pm[1] !== "127.0.0.1") { port = pm[2]; break }
      }
      if (!port) continue

      var protocol = ovr.protocol || _resolveProtocol(port)
      var url = protocol + "://" + hostForUrl + ":" + port
      var category = ovr.category || _resolveCategory(containerName)
      var iconFile = ovr.iconFile || _resolveIconFile(containerName)
      var iconLetter = ovr.icon || ""
      var color = ovr.color || categoryColors[category] || "#94A3B8"
      var name = ovr.name || _displayName(containerName)

      results.push({
        rawName: containerName,
        name: name,
        url: url,
        port: port,
        category: category,
        color: color,
        iconFile: iconFile,
        icon: iconLetter,
        image: image
      })
    }

    results.sort(function(a, b) {
      if (a.category !== b.category) return a.category.localeCompare(b.category)
      return a.name.localeCompare(b.name)
    })

    return results
  }

  // ─── Discovery (SSH + docker ps OR manual) ───────────────────────────────
  function runDiscovery() {
    if (discoveryState === "loading") return
    if (!activeServer) {
      discoveryState = "error"
      discoveryError = "Nenhum servidor configurado"
      return
    }

    // Manual server: skip SSH, use predefined services
    var manual = activeServer.manualServices
    if (manual && Array.isArray(manual) && manual.length > 0) {
      var processed = manual.map(function(s) {
        var category = s.category || _resolveCategory(s.name || "")
        return {
          rawName: s.name || s.url,
          name: s.name || s.url,
          url: s.url,
          port: "",
          category: category,
          color: s.color || categoryColors[category] || "#94A3B8",
          iconFile: s.iconFile || _resolveIconFile(s.name || ""),
          icon: s.icon || "",
          image: "manual"
        }
      })
      var nc = Object.assign({}, cacheByServer)
      nc[activeServerId] = { generatedAt: Date.now(), services: processed }
      cacheByServer = nc
      discoveryState = "ok"
      discoveryError = ""
      Logger.i("ServerDashboard", "Manual mode [" + activeServerId + "]: " + processed.length + " services")
      _saveCache()
      refresh()
      return
    }

    discoveryState = "loading"
    discoveryError = ""

    var sshCmd = "ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -p "
                 + sshPort + " " + sshUser + "@" + sshHost
                 + " 'docker ps --format \"{{.Names}}|{{.Ports}}|{{.Image}}\"'"

    discoveryProcess.targetServerId = activeServerId
    discoveryProcess.targetHost = sshHost
    discoveryProcess.command = ["sh", "-c", sshCmd]
    discoveryProcess.running = true
  }

  Process {
    id: discoveryProcess
    property string targetServerId: ""
    property string targetHost: ""

    stdout: StdioCollector { id: discoveryStdout }
    stderr: StdioCollector { id: discoveryStderr }

    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        var allOutput = String(discoveryStderr.text || "") + "\n" + String(discoveryStdout.text || "")
        var err = allOutput.trim()

        // Auto-recovery: if user is wrong (doesn't exist OR no key), try to detect another that works
        var shouldRecover = (err.indexOf("failed to look up local user") !== -1
                             || err.indexOf("Permission denied") !== -1
                             || err.indexOf("publickey") !== -1)
                            && !root._recoveryAttempted[targetServerId]
        if (shouldRecover) {
          var ra = Object.assign({}, root._recoveryAttempted)
          ra[targetServerId] = true
          root._recoveryAttempted = ra

          Logger.i("ServerDashboard", "Auto-detecting user for [" + targetServerId + "]...")
          root.discoveryState = "loading"
          root.discoveryError = "Detectando usuário SSH correto..."

          // Find the server to get host/port
          var srv = null
          for (var i = 0; i < root.servers.length; i++) {
            if (root.servers[i].id === targetServerId) { srv = root.servers[i]; break }
          }
          if (srv) {
            root.detectUserFor(srv.host, srv.port || 22, srv.user, function(detected) {
              if (detected && detected !== srv.user) {
                Logger.i("ServerDashboard", "Auto-detected user '" + detected + "' for " + targetServerId + ", retrying")
                root.editServer(targetServerId, { user: detected })
                // editServer triggers runDiscovery if it's the active server
              } else {
                root.discoveryState = "error"
                root.discoveryError = "Nenhum usuário SSH funcionou neste servidor. Edite manualmente."
              }
            })
            return
          }
        }

        root.discoveryState = "error"
        if (err.indexOf("failed to look up local user") !== -1
            || err.indexOf("Permission denied") !== -1
            || err.indexOf("publickey") !== -1) {
          root.discoveryError = "Nenhum usuário SSH funcionou neste servidor (tentei root, ubuntu, debian, fedora, etc). Verifique se a chave SSH está copiada (ssh-copy-id)."
        } else if (err.indexOf("Connection refused") !== -1
                   || err.indexOf("No route") !== -1
                   || err.indexOf("Operation timed out") !== -1
                   || err.indexOf("Connection timed out") !== -1) {
          root.discoveryError = "Servidor inalcançável — Tailscale conectado?"
        } else if (err.indexOf("Permission denied") !== -1 || err.indexOf("publickey") !== -1) {
          root.discoveryError = "SSH negado — rode: ssh-copy-id " + root.sshUser + "@" + root.sshHost
        } else if (err.indexOf("docker: command not found") !== -1
                   || err.indexOf("docker not found") !== -1
                   || err.indexOf("command not found") !== -1) {
          root.discoveryError = "Docker não encontrado no servidor (ou user sem permissão no grupo docker)"
        } else {
          // Strip the harmless "Warning: Permanently added..." prefix
          var clean = err.replace(/^Warning: Permanently added[^\n]*\n?/g, "").trim()
          root.discoveryError = clean.substring(0, 200) || "Erro desconhecido (exit " + exitCode + ")"
        }
        Logger.e("ServerDashboard", "Discovery failed [" + targetServerId + "]: " + root.discoveryError)
        return
      }

      var parsed = root._parseDockerOutput(discoveryStdout.text, targetHost)

      var newCache = Object.assign({}, root.cacheByServer)
      newCache[targetServerId] = {
        generatedAt: Date.now(),
        services: parsed
      }
      root.cacheByServer = newCache
      root.discoveryState = "ok"
      root.discoveryError = ""
      // Clear recovery flag on success so future failures can retry
      var ra = Object.assign({}, root._recoveryAttempted)
      delete ra[targetServerId]
      root._recoveryAttempted = ra
      Logger.i("ServerDashboard", "Discovery OK [" + targetServerId + "]: " + parsed.length + " services")
      root._saveCache()

      // Only refresh health if discovery was for current active server
      if (targetServerId === root.activeServerId) {
        root.refresh()
      }
    }
  }

  // ─── Cache ───────────────────────────────────────────────────────────────
  function _loadCache() {
    cacheReader.command = ["cat", cacheFile]
    cacheReader.running = true
  }

  Process {
    id: cacheReader
    stdout: StdioCollector { id: cacheReaderOut }
    stderr: StdioCollector {}
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var cache = JSON.parse(String(cacheReaderOut.text || "{}"))
        if (cache.servers && typeof cache.servers === "object") {
          root.cacheByServer = cache.servers
          Logger.i("ServerDashboard", "Loaded cache for " + Object.keys(cache.servers).length + " server(s)")
        }
      } catch (e) {
        Logger.w("ServerDashboard", "Cache parse failed: " + e)
      }
    }
  }

  function _saveCache() {
    var data = JSON.stringify({ servers: root.cacheByServer }, null, 2)
    var b64 = Qt.btoa(data)
    cacheWriter.command = ["sh", "-c", "echo " + JSON.stringify(b64) + " | base64 -d > " + JSON.stringify(cacheFile)]
    cacheWriter.running = true
  }
  Process { id: cacheWriter }

  // ─── Health check ────────────────────────────────────────────────────────
  function refresh() {
    if (isChecking || services.length === 0) return
    isChecking = true

    var script = 'printf "%s\\n" "$@" | xargs -P 8 -I {} sh -c \'code=$(curl -k -s -o /dev/null -w "%{http_code}" -m 3 --connect-timeout 2 "$1" 2>/dev/null); printf "%s|%s\\n" "$1" "$code"\' _ {}'

    var cmd = ["sh", "-c", script, "_"]
    for (var i = 0; i < services.length; i++) cmd.push(services[i].url)
    healthProcess.command = cmd
    healthProcess.running = true
  }

  Process {
    id: healthProcess
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var newStatuses = {}
        // Preserve statuses for other-server URLs
        for (var k in root.statuses) newStatuses[k] = root.statuses[k]

        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("|")
          if (parts.length < 2) continue
          var url = parts[0]
          var code = parseInt(parts[1], 10) || 0
          newStatuses[url] = (code > 0 && code < 600) ? "up" : "down"
        }
        root.statuses = newStatuses
        root.lastCheckAt = Date.now()
      }
    }
    stderr: StdioCollector {}
    onExited: function(exitCode) { root.isChecking = false }
  }

  // ─── Server management ───────────────────────────────────────────────────
  function _saveServers(serversArr, newActiveId) {
    if (!pluginApi || !pluginApi.pluginSettings) return
    pluginApi.pluginSettings.servers = serversArr
    if (newActiveId !== undefined) {
      pluginApi.pluginSettings.activeServerId = newActiveId
    }
    pluginApi.saveSettings()
  }

  function switchServer(id) {
    if (!id) return false
    var found = false
    for (var i = 0; i < servers.length; i++) {
      if (servers[i].id === id) { found = true; break }
    }
    if (!found) {
      Logger.w("ServerDashboard", "switchServer: id not found: " + id)
      return false
    }
    if (!pluginApi || !pluginApi.pluginSettings) return false
    pluginApi.pluginSettings.activeServerId = id
    pluginApi.saveSettings()
    Logger.i("ServerDashboard", "Switched to server: " + id)

    if (!cacheByServer[id]) {
      runDiscovery()
    } else {
      // Server has cached data — clear stale state from previous server
      discoveryState = "ok"
      discoveryError = ""
      refresh()
    }
    return true
  }

  function editServer(id, updates) {
    if (!id || !updates) return false
    var arr = servers.slice()
    var idx = -1
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].id === id) { idx = i; break }
    }
    if (idx === -1) return false
    var merged = Object.assign({}, arr[idx], updates)
    merged.id = arr[idx].id   // never change id
    arr[idx] = merged
    _saveServers(arr)
    // Clear cache for this server since SSH config may have changed
    var nc = Object.assign({}, cacheByServer)
    delete nc[id]
    cacheByServer = nc
    _saveCache()
    Logger.i("ServerDashboard", "Edited server: " + id)
    // If this was the active server, rerun discovery with new config
    if (id === activeServerId) runDiscovery()
    return true
  }

  function addServer(srv) {
    if (!srv || !srv.id || !srv.host) {
      Logger.w("ServerDashboard", "addServer: invalid server (need id + host)")
      return false
    }
    var arr = servers.slice()
    // Replace if id already exists
    var existing = -1
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].id === srv.id) { existing = i; break }
    }
    // Merge with existing to preserve custom fields like manualServices
    var base = existing >= 0 ? arr[existing] : {}
    var entry = Object.assign({}, base, srv, {
      id: srv.id,
      name: srv.name || base.name || srv.id,
      host: srv.host,
      user: srv.user || base.user || defaultSshUser,
      port: srv.port || base.port || 22
    })
    if (existing >= 0) arr[existing] = entry
    else arr.push(entry)
    _saveServers(arr)
    Logger.i("ServerDashboard", "Added server: " + entry.id)
    return true
  }

  function removeServer(id) {
    var arr = servers.filter(function(s) { return s.id !== id })
    if (arr.length === servers.length) return false
    var newActive = activeServerId === id && arr.length > 0 ? arr[0].id : undefined
    _saveServers(arr, newActive)
    // Clean cache
    var nc = Object.assign({}, cacheByServer)
    delete nc[id]
    cacheByServer = nc
    _saveCache()
    Logger.i("ServerDashboard", "Removed server: " + id)
    return true
  }

  // ─── User auto-detection ─────────────────────────────────────────────────
  // Probes a list of common SSH users in parallel. Returns the first that connects.
  // candidateUsers: array of strings; priorityUser: user to put first
  function detectUserFor(host, port, priorityUser, callback) {
    if (!host) { callback(""); return }

    var candidates = []
    if (priorityUser && priorityUser !== "") candidates.push(priorityUser)
    var defaults = ["root", "ubuntu", "debian", "fedora", "ec2-user", "admin", "opc", "centos", "arch", "th"]
    for (var i = 0; i < defaults.length; i++) {
      if (defaults[i] !== priorityUser) candidates.push(defaults[i])
    }

    var userList = candidates.join(" ")
    // For each candidate, ssh with `true` (no-op). Print user that worked. head -1 picks first.
    var script =
      'for u in $@; do ' +
      '  (ssh -o ConnectTimeout=2 -o BatchMode=yes -o StrictHostKeyChecking=accept-new ' +
      '   -p ' + port + ' "$u@' + host + '" true 2>/dev/null && echo "$u") & ' +
      'done; wait; '
    // The script outputs every working user; we sort by candidate order via the caller.

    var cmd = ["sh", "-c", script + " | head -10", "_"]
    for (var j = 0; j < candidates.length; j++) cmd.push(candidates[j])

    var proc = Qt.createQmlObject(
      'import QtQuick; import Quickshell.Io; Process { ' +
      '  property var _cb: null; ' +
      '  property var _candidates: []; ' +
      '  stdout: StdioCollector { ' +
      '    onStreamFinished: { ' +
      '      var working = String(text || "").trim().split("\\n").filter(function(s){ return s.length > 0 }); ' +
      '      var picked = ""; ' +
      '      for (var k = 0; k < _candidates.length; k++) { ' +
      '        if (working.indexOf(_candidates[k]) !== -1) { picked = _candidates[k]; break } ' +
      '      } ' +
      '      if (_cb) _cb(picked); ' +
      '    } ' +
      '  } ' +
      '  stderr: StdioCollector {} ' +
      '  onExited: function(exitCode) { destroy() } ' +
      '}',
      root, "UserDetect_" + Date.now())
    proc._cb = callback
    proc._candidates = candidates
    proc.command = cmd
    proc.running = true
  }

  // Adds a server with auto-detected user (used by Tailscale import + manual without user)
  function autoAddServer(srv) {
    if (!srv || !srv.id || !srv.host) return false

    // Mark detecting for UI
    var nd = Object.assign({}, userDetecting)
    nd[srv.id] = true
    userDetecting = nd

    detectUserFor(srv.host, srv.port || 22, srv.user || defaultSshUser, function(user) {
      var nd2 = Object.assign({}, root.userDetecting)
      delete nd2[srv.id]
      root.userDetecting = nd2

      var finalUser = user || srv.user || root.defaultSshUser
      root.addServer({
        id: srv.id,
        name: srv.name || srv.id,
        host: srv.host,
        user: finalUser,
        port: srv.port || 22
      })
      Logger.i("ServerDashboard", "autoAddServer [" + srv.id + "] detected user: " + (user || "(fallback: " + finalUser + ")"))
    })
    return true
  }

  // ─── Tailscale peer listing ──────────────────────────────────────────────
  function listTailscalePeers() {
    if (tailscaleListing) return
    tailscaleListing = true
    tailscaleProcess.running = true
  }

  Process {
    id: tailscaleProcess
    command: ["tailscale", "status", "--json"]
    stdout: StdioCollector { id: tailscaleOut }
    stderr: StdioCollector {}

    onExited: function(exitCode) {
      root.tailscaleListing = false
      if (exitCode !== 0) {
        Logger.w("ServerDashboard", "tailscale status failed")
        return
      }
      try {
        var d = JSON.parse(String(tailscaleOut.text || "{}"))
        var peers = []
        var existingIds = {}
        for (var i = 0; i < root.servers.length; i++) existingIds[root.servers[i].id] = true

        var allPeers = d.Peer || {}
        for (var key in allPeers) {
          var p = allPeers[key]
          if (!p.Online) continue
          var ipv4 = (p.TailscaleIPs || []).filter(function(ip) { return ip.indexOf(":") === -1 })
          var hostName = p.HostName || (p.DNSName || "").split(".")[0]
          if (!hostName || !ipv4[0]) continue
          peers.push({
            id: hostName,
            name: hostName,
            host: ipv4[0],
            user: root.defaultSshUser,
            port: 22,
            os: p.OS || "",
            alreadyAdded: !!existingIds[hostName]
          })
        }
        peers.sort(function(a, b) { return a.name.localeCompare(b.name) })
        root.tailscalePeers = peers
        Logger.i("ServerDashboard", "Tailscale peers found: " + peers.length)
      } catch (e) {
        Logger.e("ServerDashboard", "tailscale status parse: " + e)
      }
    }
  }

  // ─── Timers ──────────────────────────────────────────────────────────────
  Timer {
    id: discoveryTimer
    interval: root.discoveryInterval
    repeat: true
    running: true
    triggeredOnStart: false
    onTriggered: root.runDiscovery()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshInterval
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  onRefreshIntervalChanged: refreshTimer.interval = refreshInterval
  onDiscoveryIntervalChanged: discoveryTimer.interval = discoveryInterval

  Component.onCompleted: {
    _loadCache()
    initialTimer.start()
  }

  Timer {
    id: initialTimer
    interval: 1500
    repeat: false
    onTriggered: root.runDiscovery()
  }

  // ─── IPC ─────────────────────────────────────────────────────────────────
  IpcHandler {
    target: "plugin:server-dashboard"

    function refresh(): string {
      root.refresh()
      return "refresh triggered"
    }

    function discover(): string {
      root.runDiscovery()
      return "discovery triggered for " + root.activeServerId
    }

    function open(name: string): string {
      var q = name.toLowerCase()
      for (var i = 0; i < root.services.length; i++) {
        if (root.services[i].name.toLowerCase() === q
            || root.services[i].rawName.toLowerCase() === q) {
          root.openService(root.services[i].url)
          return "opened " + root.services[i].name
        }
      }
      return "not found: " + name
    }

    function switchServer(id: string): string {
      return root.switchServer(id) ? ("switched to " + id) : ("not found: " + id)
    }

    function editServerUser(id: string, newUser: string): string {
      return root.editServer(id, { user: newUser }) ? ("edited " + id) : ("not found: " + id)
    }

    function removeServer(id: string): string {
      return root.removeServer(id) ? ("removed " + id) : ("not found: " + id)
    }

    function autoDetect(id: string): string {
      var srv = null
      for (var i = 0; i < root.servers.length; i++) {
        if (root.servers[i].id === id) { srv = root.servers[i]; break }
      }
      if (!srv) return "not found: " + id
      root.detectUserFor(srv.host, srv.port || 22, srv.user, function(detected) {
        if (detected) {
          Logger.i("ServerDashboard", "Manual detect [" + id + "]: " + detected)
          root.editServer(id, { user: detected })
        } else {
          Logger.w("ServerDashboard", "Manual detect [" + id + "]: no user worked")
        }
      })
      return "detecting for " + id
    }

    function listServers(): string {
      return JSON.stringify(root.servers)
    }

    function listTailscale(): string {
      root.listTailscalePeers()
      return "listing tailscale peers"
    }

    function togglePanel() {
      pluginApi.withCurrentScreen(function(screen) { pluginApi.togglePanel(screen) })
    }

    function status(): string {
      return JSON.stringify({
        active: root.activeServerId,
        total: root.totalCount,
        up: root.upCount,
        discoveryState: root.discoveryState,
        discoveryError: root.discoveryError,
        lastDiscovery: root.lastDiscoveryAt,
        lastCheck: root.lastCheckAt
      })
    }
  }
}
