# Paper Server Starter Kits

One command to set up a Paper or Velocity Minecraft server with essential plugins pre-installed.

## Prerequisites

- **Java 17** for Minecraft `1.18.x` – `1.20.4`
- **Java 21** for Minecraft `1.20.5` – `1.21.x`
- **Java 25** for 2026 drop releases (`26.1`, etc.)
- **curl** — download server JARs and plugins
- **jq** — parse manifests
- **ruby** — parse kit YAML (built into macOS)

On first run, `./setup.sh` creates a `.env` file from `.env.example` with your chosen defaults (Minecraft version, memory, etc.). Edit `.env` to change defaults for future runs.

## Minecraft versioning

Mojang changed versioning in 2026 from the old `1.x` scheme to **year-based drop releases**:

| Format | Example | Meaning |
|--------|---------|---------|
| Legacy | `1.21.11` | Last pre-2026 numbering |
| Drop | `26.1` | First release drop of 2026 |
| Drop patch | `26.1.1` | First hotfix for that drop |
| Drop hotfix | `26.1.2` | Second hotfix for that drop |

This project queries the [PaperMC downloads API](https://papermc.io/downloads) (`fill.papermc.io`) for available versions. Set `MC_VERSION=latest` in `.env` (the default) to always use the newest **supported** Paper build (currently a 26.x drop release such as `26.1.2`).

All Paper versions from `1.7.10` through the latest drop are available — pick one in the setup wizard or pass `--mc-version`.

## Quick start

```bash
./setup.sh
```

The interactive wizard walks you through:

1. Choosing a starter kit
2. Naming each server (consoles, LuckPerms, attach commands)
3. Minecraft version (default `latest` — resolved from PaperMC)
3. Memory per server (default `2G`)
4. Setup only or setup + start

No kit name required — just run the script and follow the prompts.

## Starter kits

| Kit | Description | Connect |
|-----|-------------|---------|
| `paper-basic` | Single Paper survival server | `localhost:25565` |
| `velocity-basic` | Velocity proxy only | `localhost:25565` |
| `velocity-paper` | Velocity + one Paper backend (lobby) | `localhost:25565` |
| `velocity-multi` | Velocity + lobby + survival Paper backends | `localhost:25565` |
| `velocity-fabric` | Velocity + optimized Fabric lobby + survival | `localhost:25565` |

## Included plugins

### Paper servers

- **LuckPerms** — permissions
- **Chunky** — world pre-generation
- **EssentialsX** — `/home`, `/spawn`, `/tpa`, etc.
- **Vault** — economy/permissions API
- **PlaceholderAPI** — placeholders
- **Simple Voice Chat** — proximity voice chat (players need the [client mod](https://modrinth.com/mod/simple-voice-chat) too)

### Velocity proxy

- **LuckPerms-Velocity** — proxy-side permissions
- **Simple Voice Chat** — routes voice between backend servers on a network

Customize plugins in [`kits/_shared/plugins-paper.json`](kits/_shared/plugins-paper.json) and [`kits/_shared/plugins-velocity.json`](kits/_shared/plugins-velocity.json).

### Fabric servers (`velocity-fabric`)

Server-side optimization mods (players join with a **vanilla client** matching your MC version — no mods required on the client):

| Mod | Purpose |
|-----|---------|
| **Fabric API** | Required library |
| **Lithium** | Physics, mob AI, and tick optimizations |
| **FerriteCore** | Lower RAM usage |
| **Krypton** | Network stack optimizations |
| **BadOptimizations** | Miscellaneous engine fixes |
| **Chunky** | World pre-generation (`/chunky start`) |
| **FabricProxy-Lite** | Velocity modern forwarding on Fabric backends |
| **Simple Voice Chat** | Proximity voice chat (install the client mod to talk) |

Customize mods in [`kits/_shared/mods-fabric.json`](kits/_shared/mods-fabric.json).

**8 GB host tip:** allocate ~`1G` to the proxy and ~`5G`–`6G` per Fabric backend (`--memory 5G`), or run the proxy on a separate small VPS.

## Non-interactive usage

Skip the wizard by passing a kit name:

```bash
./setup.sh paper-basic
./setup.sh velocity-multi --setup-only
./setup.sh paper-basic --memory 4G --mc-version latest
./setup.sh paper-basic --mc-version 1.21.11
```

### Options

| Flag | Description |
|------|-------------|
| `--setup-only` | Download and configure without starting |
| `--mc-version` | Minecraft version or `latest` (Paper only; Velocity uses its own versioning) |
| `--memory` | JVM heap per server (e.g. `2G`, `4G`) |

## Managing servers

```bash
# Start after setup-only
./scripts/start-kit.sh paper-basic

# Attach to a server's live console by unique name
./scripts/attach-server.sh multi-lobby

# List consoles for a kit
./scripts/attach-kit.sh velocity-multi

# Stop all servers in a kit
./scripts/stop-kit.sh paper-basic

# Stop everything — all kits, tmux sessions, and Minecraft ports
./stop-all.sh
```

### Live consoles (tmux)

Each server has a **unique name** and its own tmux session (like a dedicated `screen` per server).

| Server name (velocity-multi) | tmux session | Attach |
|------------------------------|--------------|--------|
| `multi-proxy` | `mc-multi-proxy` | `./scripts/attach-server.sh multi-proxy` |
| `multi-lobby` | `mc-multi-lobby` | `./scripts/attach-server.sh multi-lobby` |
| `multi-survival` | `mc-multi-survival` | `./scripts/attach-server.sh multi-survival` |

```bash
# List all consoles for a kit
./scripts/attach-kit.sh velocity-multi

# Attach to one server by its unique name
./scripts/attach-server.sh multi-lobby
```

Your chosen names are used for:

- **Server folders** — `servers/<kit>/<your-name>/`
- **tmux sessions** — `mc-<your-name>`
- **LuckPerms** — `server-name` in config
- **Velocity** — `/server <your-name>` routing

During `./setup.sh`, the wizard prompts for each name. Defaults come from `kit.yml` if you press Enter.

Set default names in `kits/<kit>/kit.yml` (optional — wizard overrides are saved to `servers/<kit>/.server-names.json`):

```yaml
servers:
  - id: paper-lobby
    name: multi-lobby    # default suggestion in wizard
    type: paper
    port: 25566
```

If you rename servers and re-run setup, remove old folders under `servers/<kit>/` that used the previous names.

| Keys | Action |
|------|--------|
| `Ctrl-b d` | Detach — server keeps running |

Install tmux if needed: `brew install tmux`

For headless/background mode (logs only in `console.log`):

```bash
./scripts/start-kit.sh paper-basic --background
# or set CONSOLE_MODE=background in .env
```

Logs (background mode): `servers/<kit>/<server>/console.log`

## Project layout

```
setup.sh              # Main entry — interactive wizard
scripts/              # Download, install, start/stop logic
kits/                 # Starter kit manifests and config templates
servers/              # Generated at runtime (gitignored)
```

## Adding a new kit

1. Create `kits/my-kit/kit.yml` with `id`, `name`, `description`, and `servers`
2. Add templates under `kits/my-kit/templates/<server-id>/`
3. Run `./setup.sh` — your kit appears in the menu automatically

## Velocity forwarding

Velocity kits auto-generate a `forwarding.secret` shared between the proxy and Paper backends. Paper backends run with `online-mode=false`; authentication is handled by the proxy.

**Server list version** — Velocity is configured with `ping-passthrough = "ALL"` so the multiplayer list shows your Paper backend version (e.g. `26.1.2`) instead of Velocity's default `1.21.11` ping response.

**26.x clients** — Velocity `3.4.0` only accepts clients through `1.21.11`. For `26.1.2` backends, setup auto-downloads **Velocity `3.5.0-SNAPSHOT`**. Set `VELOCITY_VERSION=` in `.env` to override.

### Fabric + Velocity forwarding

Fabric backends run with `online-mode=false`; Velocity handles authentication. **FabricProxy-Lite** is pre-configured with the shared `forwarding.secret`. Players must connect through the proxy (`localhost:25565`), not directly to backend ports.

## LuckPerms network sync (Velocity kits)

Velocity kits (`velocity-paper`, `velocity-multi`, `velocity-basic`) configure **LuckPerms** to sync permissions across every server in the network:

| Setting | What it does |
|---------|----------------|
| **Shared H2 database** | One permission database at `servers/<kit>/.luckperms/` — all servers read/write the same data |
| **`messaging-service: pluginmsg`** | Changes propagate instantly via Velocity's plugin messaging channel |
| **Unique `server-name`** | Each server's `name` in `kit.yml` (e.g. `multi-lobby`) — used for LuckPerms context and tmux sessions |

### How to use it

1. Set up a Velocity kit: `./setup.sh velocity-multi`
2. Start all servers: permissions sync automatically
3. Run LuckPerms commands from **any** server or the proxy — they apply network-wide

```bash
# Examples (run on proxy or any backend)
lp user Steve permission set essentials.home true
lp group default permission set essentials.sethome true
lp sync    # force a full sync if needed
```

### Standalone Paper (`paper-basic`)

Single-server kits use a local LuckPerms database — no network sync needed.

### Upgrading to MySQL (optional)

For larger networks or multiple hosts, switch all `plugins/LuckPerms/config.yml` files to the same MySQL database. See the [LuckPerms network guide](https://luckperms.net/wiki/Network-Installation).

## Troubleshooting

**Java version error** — Setup auto-detects the right JDK from Homebrew (`openjdk@17`, `openjdk@21`, `openjdk@25`). Install the version you need:

```bash
brew install openjdk@25   # for 26.x drop releases
brew install openjdk@21   # for 1.20.5 – 1.21.x
brew install openjdk@17   # for 1.18.x – 1.20.4
```

**Port already in use** — Stop existing servers or change ports in `kits/<kit>/kit.yml`

**Plugin download failed** — Check network; Hangar/LuckPerms APIs must be reachable

**Re-running setup** — Safe to re-run; existing plugin configs are not overwritten

## License

MIT — use freely for your Minecraft projects.
