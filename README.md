# Server Dashboard

Multi-server homelab dashboard for [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell). Auto-discovers services on remote hosts via SSH + Docker, renders them as clickable tiles in a panel, opens them in the browser. Replaces Dashy / Homarr / Homepage without leaving the shell.

![Server Dashboard panel showing services from a Fedora server](screenshots/server-dashboard-fedora.png)

---

## Features

- Auto-discovery via SSH + `docker ps` on the remote host. Tiles are containers with an HTTP-reachable port.
- Multi-server, with a switcher in the panel header.
- Tailscale peer import — one-click "Add" for any online peer.
- Auto-detect of SSH user. Tries `root`, `ubuntu`, `debian`, `fedora`, `ec2-user`, `admin`, `opc`, `centos`, `arch` plus your default and picks the first that connects.
- Real service logos via [homarr-labs/dashboard-icons](https://github.com/homarr-labs/dashboard-icons) (30 bundled). Falls back to a colored letter tile for unknowns.
- Parallel `curl` health check every 30s, color-coded status dot per tile.
- Smart categorization — containers grouped by regex rules (Media, Cloud, Dev, Pentest, Home, Infra, etc).
- Per-container overrides — rename, recolor, recategorize, hide, custom icon.
- Manual mode — for hosts without SSH (or for monitoring external URLs), hardcode a service list per server.
- Per-server discovery cache, so the panel opens instantly even when SSH is slow.

---

## Installation

### As a custom plugin source

Edit `~/.config/noctalia/plugins.json`:

```json
{
  "sources": [
    { "enabled": true, "name": "Noctalia Plugins", "url": "https://github.com/noctalia-dev/noctalia-plugins" },
    { "enabled": true, "name": "Server Dashboard", "url": "https://github.com/ThiagoFrag/noctalia-server-dashboard" }
  ],
  "states": {
    "server-dashboard": { "enabled": true }
  }
}
```

Restart Noctalia (`pkill -f "qs -c noctalia-shell"; qs -c noctalia-shell &`). The plugin downloads on next start.

### Manual install

```bash
git clone https://github.com/ThiagoFrag/noctalia-server-dashboard.git \
  ~/.config/noctalia/plugins/server-dashboard

jq '.states["server-dashboard"] = {"enabled": true}' \
  ~/.config/noctalia/plugins.json > /tmp/p.json && mv /tmp/p.json ~/.config/noctalia/plugins.json
```

Add the bar widget via Settings → Bar → add `plugin:server-dashboard`.

### Requirements

- Noctalia Shell 4.0 or later
- `curl`, `ssh` on the client. `docker` on the remote host.
- Optional: `tailscale` on the client (only needed for the import feature).

---

## Configuration

All settings live in `~/.config/noctalia/plugins/server-dashboard/settings.json`. The plugin's Settings UI handles the common cases (servers, intervals, count badge). For advanced stuff (overrides, category rules, icon map) edit the JSON directly with Noctalia stopped (the plugin overwrites the file on save).

### Adding a server

Three ways:

1. Settings → Servers → "+ Importar do Tailscale" — lists online peers; "+ Adicionar (auto)" detects the SSH user automatically.
2. Settings → Servers → "+ Adicionar manual" — fill in host, user, port.
3. Edit `settings.json` directly while Noctalia is stopped.

### Server config shape

```json
{
  "servers": [
    {
      "id": "fedora-server",
      "name": "Fedora Server",
      "host": "100.118.33.37",
      "user": "th",
      "port": 22
    },
    {
      "id": "vps-1",
      "name": "Some VPS (no SSH access)",
      "host": "1.2.3.4",
      "manualServices": [
        { "name": "My App", "url": "http://1.2.3.4:3000", "category": "Projetos", "color": "#F2D4D7", "icon": "M" }
      ]
    }
  ],
  "activeServerId": "fedora-server"
}
```

A server with `manualServices` skips SSH+docker and shows the predefined list. Useful for boxes you don't have shell access on.

### Overriding a discovered container

Containers are matched by their raw name from `docker ps`. Override per-container:

```json
"overrides": {
  "my-app-container-1": {
    "name": "My App",
    "category": "Projetos",
    "color": "#F59E0B",
    "icon": "M",
    "iconFile": "icons/custom.png",
    "protocol": "https",
    "hidden": true
  }
}
```

### Category rules

Auto-categorization runs a list of regex against the container name. First match wins. Unmatched containers fall into "Outros".

```json
"categoryRules": [
  { "match": "jellyfin|sonarr|radarr", "category": "Media" },
  { "match": "nextcloud|immich",       "category": "Cloud" }
]
```

### Icon map

Maps service slugs to logo files. Partial matching: if the container name *contains* the slug (`immich_server` contains `immich`), the icon is used.

```json
"iconMap": {
  "jellyfin": "icons/jellyfin.png",
  "my-thing": "icons/my-thing.png"
}
```

Drop any PNG/SVG in `icons/` and reference it.

---

## IPC

Exposed via Quickshell IPC.

```bash
# Force a discovery cycle on the active server
qs -c noctalia-shell ipc call plugin:server-dashboard discover

# Health check (curl) all known services
qs -c noctalia-shell ipc call plugin:server-dashboard refresh

# Switch to another configured server
qs -c noctalia-shell ipc call plugin:server-dashboard switchServer my-vps

# Open a service in the browser by name
qs -c noctalia-shell ipc call plugin:server-dashboard open Jellyfin

# List Tailscale peers (populates internal state for the Settings UI)
qs -c noctalia-shell ipc call plugin:server-dashboard listTailscale

# Manually trigger SSH user auto-detection for a server
qs -c noctalia-shell ipc call plugin:server-dashboard autoDetect my-vps

# Edit SSH user of a server (clears its discovery cache, re-runs discovery)
qs -c noctalia-shell ipc call plugin:server-dashboard editServerUser my-vps root

# Remove a server
qs -c noctalia-shell ipc call plugin:server-dashboard removeServer my-vps

# JSON status (active server, counts, errors, timestamps)
qs -c noctalia-shell ipc call plugin:server-dashboard status

# Open the panel
qs -c noctalia-shell ipc call plugin:server-dashboard togglePanel
```

---

## How discovery works

```
panel open / 5min timer / IPC discover
                  |
       active server has manualServices?
              /              \
            yes               no
             |                 |
       use that list    ssh -o ConnectTimeout=3 -BatchMode=yes
                              user@host 'docker ps --format ...'
                                       |
                              exit code 0?
                              /           \
                           yes             no
                            |               |
                  parse {Name|Ports|Image}   err contains "user doesn't exist"
                            |                or "Permission denied"?
                  filter: port on 0.0.0.0     |
                  or Tailscale IP, not 127.x  yes (first attempt)
                            |                   |
                  apply overrides[name]    auto-detect SSH user in parallel
                            |               (10 candidates, picks first that works)
                  cache + render               |
                            |               editServer({user: detected})
                  parallel curl on each       |
                  URL (xargs -P 8, 3s         retry discovery
                  timeout) -> status dots
```

A second failure (after auto-recovery) shows the error in the panel with a retry button. The recovery flag clears once discovery succeeds.

---

## Default category colors

Override via `categoryColors` in settings.json. Per-container `color` in `overrides` always wins.

| Category | Color   |
|----------|---------|
| Media    | #7B2CBF |
| Cloud    | #0082C9 |
| Dev      | #8B5CF6 |
| Home     | #2BB67D |
| Pentest  | #DC2626 |
| Projetos | #F59E0B |
| Infra    | #64748B |
| Outros   | #94A3B8 |

---

## Troubleshooting

**Panel says "Servidor inalcançável"** — Tailscale isn't connected, or the host's IP changed. Check `tailscale status`.

**"SSH negado" or "Nenhum usuário SSH funcionou"** — your SSH key isn't on the remote host. Run `ssh-copy-id <user>@<host>` once. Auto-detection will then pick it up.

**"Docker não encontrado no servidor"** — install Docker on the remote, or ensure the SSH user is in the `docker` group so it can run `docker ps` without sudo.

**Service shows as "down" but I can open it manually** — by default any HTTP response (200, 302, 401, 403) is considered up. If your service returns 5xx, it'll show down. Adjust the curl logic in `Main.qml` if needed.

**Plugin save wipes my `manualServices`** — known limitation. Stop Noctalia (`pkill -f noctalia-shell`) before editing `settings.json` manually. The plugin's `saveSettings()` doesn't know about custom fields and may overwrite them.

---

## Credits

- [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell) — the Wayland desktop shell this plugin runs in.
- [homarr-labs/dashboard-icons](https://github.com/homarr-labs/dashboard-icons) — service logos.
- [Quickshell](https://quickshell.org/) — the QML engine powering Noctalia.

---

## License

MIT — see [LICENSE](LICENSE).
