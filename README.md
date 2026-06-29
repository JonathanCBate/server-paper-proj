# Paper Server Starter Kits

One command to set up a Paper or Velocity Minecraft server with essential plugins pre-installed.

## Prerequisites

- **Java 21+** for legacy versions (`1.21.x` and below)
- **Java 25+** for 2026 drop releases (`26.1`, `26.1.2`, etc.)
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

This project queries the [PaperMC API](https://api.papermc.io) for available versions. Set `MC_VERSION=latest` in `.env` (the default) to always use the newest stable Paper build.

If you request a version that Paper has not published yet (e.g. `26.1.2` before it ships), setup will fail with a clear message and suggest using `latest`.

## Quick start

```bash
./setup.sh
```

The interactive wizard walks you through:

1. Choosing a starter kit
2. Minecraft version (default `latest` — resolved from PaperMC)
3. Memory per server (default `2G`)
4. Setup only or setup + start

No kit name required — just run the script and follow the prompts.

## Starter kits

| Kit | Description | Connect |
|-----|-------------|---------|
| `paper-basic` | Single Paper survival server | `localhost:25565` |
| `velocity-basic` | Velocity proxy only | `localhost:25565` |
| `velocity-paper` | Velocity + one Paper backend (lobby) | `localhost:25565` |
| `velocity-multi` | Velocity + lobby + survival backends | `localhost:25565` |

## Included plugins

### Paper servers

- **LuckPerms** — permissions
- **Chunky** — world pre-generation
- **EssentialsX** — `/home`, `/spawn`, `/tpa`, etc.
- **Vault** — economy/permissions API
- **PlaceholderAPI** — placeholders

### Velocity proxy

- **LuckPerms-Velocity** — proxy-side permissions

Customize plugins in [`kits/_shared/plugins-paper.json`](kits/_shared/plugins-paper.json) and [`kits/_shared/plugins-velocity.json`](kits/_shared/plugins-velocity.json).

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

# Stop all servers in a kit
./scripts/stop-kit.sh paper-basic
```

Logs: `servers/<kit>/<server>/console.log`

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

## LuckPerms network sync (Velocity kits)

Velocity kits (`velocity-paper`, `velocity-multi`, `velocity-basic`) configure **LuckPerms** to sync permissions across every server in the network:

| Setting | What it does |
|---------|----------------|
| **Shared H2 database** | One permission database at `servers/<kit>/.luckperms/` — all servers read/write the same data |
| **`messaging-service: pluginmsg`** | Changes propagate instantly via Velocity's plugin messaging channel |
| **Unique `server-name`** | Each server (`velocity`, `paper-lobby`, `paper-survival`) is tracked separately for context-specific permissions |

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

**Java version error** — Install Java 21+: `java -version`

**Port already in use** — Stop existing servers or change ports in `kits/<kit>/kit.yml`

**Plugin download failed** — Check network; Hangar/LuckPerms APIs must be reachable

**Re-running setup** — Safe to re-run; existing plugin configs are not overwritten

## License

MIT — use freely for your Minecraft projects.
