# claude-code-safe

A standalone Docker image and wrapper scripts for running [Claude Code](https://code.claude.com/docs/en/setup) in isolated containers with firewall-restricted networking. Built for developers who need secure, reproducible Claude Code environments without per-project configuration overhead.

**Two modes of operation:**
- **`claude-safe`** — Runs containers locally. Project directory is bind-mounted directly.
- **`claude-server`** — Runs containers on a remote server (e.g., a local homelab machine). Builds survive laptop sleep/disconnect. Project is rsynced to the server; results are synced back on demand.

**Key features:**
- **One image, any project** — No `.devcontainer` folder required. Build once, mount any directory.
- **Persistent authentication** — OAuth credentials stored in a Docker volume. Authenticate once, reuse everywhere.
- **Network firewall** — iptables rules restrict outbound traffic to whitelisted domains (Claude API, GitHub, npm, Azure, Expo, PyPI, etc.)
- **Cloud CLI support** — GitHub CLI, Azure CLI, and EAS CLI (Expo) pre-installed with firewall rules configured
- **Selective SSH mounting** — Interactive server picker or explicit host list; copies only selected config blocks and keys
- **Python toolchain** — uv, ruff, and pip-audit pre-installed for Python development
- **Native installer** — Uses the official native installer (not deprecated npm package) with automatic updates
- **Zero friction** — Auto-passes `--dangerously-skip-permissions` since the container itself is the sandbox
- **Remote builds** — `claude-server` runs builds on a remote server via SSH, wrapped in tmux for detachability

Created February 2025.

---

## Quick start

### Prerequisites

- Docker Desktop (or Docker Engine on Linux)
- A Claude Max or Pro subscription (for OAuth login)
- macOS, Linux, or WSL2

### 1. Install the wrapper scripts

```bash
curl -fsSL https://raw.githubusercontent.com/albertsikkema/claude-safe/main/install.sh | bash
```

Installs `claude-safe` and `claude-server` to `~/.local/bin` (no sudo). The Docker image is pulled from the public GHCR registry automatically on first run — no build needed.

Override the install location with `CLAUDE_SAFE_PREFIX`:

```bash
CLAUDE_SAFE_PREFIX=/usr/local/bin curl -fsSL https://raw.githubusercontent.com/albertsikkema/claude-safe/main/install.sh | bash
```

Skip `claude-server` if you only want the local wrapper:

```bash
CLAUDE_SAFE_NO_SERVER=1 curl -fsSL https://raw.githubusercontent.com/albertsikkema/claude-safe/main/install.sh | bash
```

### 2. First-run authentication

```bash
claude-safe --shell
```

This drops you into a zsh shell inside the container. Then:

```bash
claude
# Select "Claude account with subscription" and authenticate via browser
# Once login succeeds, press Ctrl-C to exit Claude, then exit the shell
```

Credentials are stored in a Docker volume (`claude-code-credentials`) and persist across container restarts and image rebuilds. No re-auth required.

### 3. Run it

```bash
cd ~/my-project
claude-safe
```

That's it. The image auto-pulls on first run, then re-checks once per day for updates.

### (Optional) Remote-server mode

If you want to run Claude Code on a remote machine via `claude-server`, set the host in your shell profile:

```bash
echo 'export CLAUDE_SERVER_HOST=your-host' >> ~/.zshrc   # zsh
echo 'export CLAUDE_SERVER_HOST=your-host' >> ~/.bashrc  # bash
```

Then from any project directory:

```bash
claude-server
```

See [Remote builds with `claude-server`](#remote-builds-with-claude-server) below.

---

## Daily use

```bash
# Run Claude Code against your current directory
cd ~/my-project
claude-safe

# Run against a specific directory
claude-safe /path/to/project

# Drop into a zsh shell instead of Claude
claude-safe --shell

# Skip the firewall (faster startup, full network access)
claude-safe --no-firewall

# Mount SSH config/keys (interactive server picker)
claude-safe --ssh

# Mount SSH config/keys for specific servers
claude-safe --ssh myserver,github.com

# Mount Azure CLI credentials (~/.azure)
claude-safe --azure

# Mount Expo/EAS CLI credentials (~/.expo)
claude-safe --expo

# Full image rebuild (pulls fresh base + latest Claude Code)
claude-safe --rebuild

# Pull the latest nightly image from GHCR (see "Nightly builds" below)
claude-safe --pull

# Show all options
claude-safe --help
```

---

## Remote builds with `claude-server`

`claude-server` runs Claude Code containers on a remote server (set `CLAUDE_SERVER_HOST=<host>` in your shell profile). Builds survive laptop sleep, network drops, and lid closes.

### Setup

```bash
# 1. (Once) set the remote host
echo 'export CLAUDE_SERVER_HOST=your-host' >> ~/.zshrc
exec zsh

# 2. Pull the public GHCR image to the server
claude-server --pull

# 3. Authenticate (first time only — stored in Docker volume on the server)
claude-server --shell
# Inside: run `claude` and complete OAuth, then exit
```

If you'd rather build the image on the server from source instead of pulling, swap step 2 for `claude-server --rebuild`.

### Usage

```bash
# Start a build (prints session ID)
claude-server -p "implement feature X"

# Check progress
claude-server --status
claude-server --logs <session-id>

# Pull results back to local project
claude-server --sync <session-id>

# Interactive mode (wrapped in tmux — detach with Ctrl+B, D)
claude-server --shell
claude-server --attach <session-id>    # reattach later

# Clean up
claude-server --stop <session-id>      # stop running build
claude-server --cleanup <session-id>   # remove workspace from server

# Pull the latest nightly image from GHCR on the server
claude-server --pull
```

### How it works

1. **rsync up** — Project directory is synced to `server:~/claude-server/<session-id>/`
2. **docker run** — Container runs on the server (detached for `-p`, tmux for interactive)
3. **rsync down** — Results are synced back on demand with `--sync`

Credentials (SSH keys, Azure, Expo, GitHub CLI config) are copied to temp dirs on the server and mounted into the container, matching `claude-safe` behavior.

### Non-interactive mode (claude-safe)

Pass prompts directly to Claude for scripting and automation:

```bash
# Run a single prompt and exit
claude-safe -p "fix the bug in main.py"

# With JSON output
claude-safe -p "summarize this code" --output-format json

# With specific model or turn limit
claude-safe -p "refactor this" --model opus --max-turns 5

# Verbose output
claude-safe -p "explain this code" --verbose

# Against a specific directory
claude-safe /path/to/project -p "explain this code"

# Pass additional claude args after --
claude-safe -- --allowedTools 'Read,Grep' -p 'search for bugs'
```

The flags `-p`, `--output-format`, `--verbose`, `--max-turns`, and `--model` are passed through directly to Claude. Any other Claude arguments can be passed after `--`.

### What gets mounted

| Host path | Container path | Type | Purpose |
|---|---|---|---|
| `$PWD` (or arg) | `/workspace` | bind mount | Your project files |
| `claude-code-credentials` | `/home/node/.claude` | Docker volume | Auth credentials (persisted) |
| `~/.cache/uv` | `/home/node/.cache/uv` | bind mount | uv/uvx cache (MCP servers, packages) |
| (env vars) | `GIT_AUTHOR_NAME`, etc. | environment | Git user identity (extracted from host `git config`) |
| (env var) | `GH_TOKEN` | environment | GitHub auth token (extracted from host via `gh auth token`) |
| `~/.ssh` (selected) | `/home/node/.ssh` | bind mount (ro) | SSH config/keys for selected servers (with `--ssh` flag) |
| `~/.config/gh` | `/home/node/.config/gh` | bind mount (ro) | GitHub CLI config (with `--github` flag) |
| `~/.azure` | `/home/node/.azure` | bind mount | Azure CLI credentials (with `--azure` flag) |
| `~/.expo` | `/home/node/.expo` | bind mount | EAS CLI credentials (with `--expo` flag) |
| `claude-code-history` | `/commandhistory` | Docker volume | Shell history (persisted) |

---

## Native installer (not npm)

Anthropic has deprecated npm installation of Claude Code. The Dockerfile uses the **native installer**:

```dockerfile
RUN mkdir -p /tmp/claude-install && cd /tmp/claude-install \
    && curl -fsSL https://claude.ai/install.sh | bash \
    && rm -rf /tmp/claude-install
```

Source: [Claude Code setup docs](https://code.claude.com/docs/en/setup) — _"NPM installation is deprecated. Use the native installation method when possible."_

Some newer features are native-only and will never ship to npm. See [this confirmation from Anthropic staff](https://x.com/EricBuess/status/2001035072116547595).

### OOM bug workaround

The native installer consumes excessive memory when run as root or from a large working directory during `docker build`, causing OOM kills. This is a known regression:

**Bug:** [anthropics/claude-code#22536](https://github.com/anthropics/claude-code/issues/22536) — _"Claude Code installer OOM when run as root during Docker build"_ (filed 2026-02-02)

**Workaround used in this Dockerfile:**
- The install runs as `USER node` (non-root), not root
- `cd /tmp/claude-install` ensures a small, empty working directory
- The temp directory is cleaned up after install

If the bug is fixed upstream, the `mkdir`/`cd`/`rm` wrapper can be simplified to just `RUN curl -fsSL https://claude.ai/install.sh | bash`.

---

## Nightly builds (GHCR)

`.github/workflows/nightly-build.yml` builds the image every night at 03:00 UTC
(plus on demand and on Dockerfile / firewall changes) and pushes it to GitHub
Container Registry as a multi-arch `linux/amd64,linux/arm64` image.

Tags:
- `ghcr.io/albertsikkema/claude-code-safe:latest`
- `ghcr.io/albertsikkema/claude-code-safe:YYYY-MM-DD`

The package is **public** — `docker pull` works without authentication. The wrappers handle pulling and retagging:

```bash
claude-safe --pull            # local
claude-server --pull          # remote ($CLAUDE_SERVER_HOST)
```

Both also auto-pull on first run and re-check once per day.

Override the source image with `CLAUDE_SAFE_REMOTE_IMAGE`. To trigger a build
manually instead of waiting for cron:

```bash
gh workflow run nightly-build.yml
```

---

## Build from source

For contributors, or if you want to modify the Dockerfile / firewall / wrappers:

```bash
git clone https://github.com/albertsikkema/claude-safe.git
cd claude-safe

make build-local        # docker build --no-cache --pull -t claude-code-safe .
make install-local      # /usr/local/bin/claude-safe (sudo)
make install-server     # /usr/local/bin/claude-server (sudo)
```

The `Makefile` also exposes `clean-local`, `clean-server SERVER=<host>`, `cleanup-server`, and `build-server` (builds on the remote via SSH). Run `make help` for the full list.

Set `CLAUDE_SAFE_DIR` to the cloned directory if you want `claude-safe --rebuild` to work after installing the wrapper script outside the repo:

```bash
echo 'export CLAUDE_SAFE_DIR=$HOME/claude-safe' >> ~/.zshrc
```

---

## Network firewall

When `claude-safe` runs (without `--no-firewall`), the container sets up iptables rules that **deny all outbound HTTP/HTTPS traffic except to whitelisted domains**:

**Allowed:**
- `api.anthropic.com`, `auth.anthropic.com`, `console.anthropic.com`, `claude.ai` (Claude API + auth)
- `statsig.anthropic.com`, `sentry.io` (telemetry)
- `registry.npmjs.org` (package installs)
- `github.com`, `api.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `github-cloud.s3.amazonaws.com` (git operations)
- `login.microsoftonline.com`, `management.azure.com`, `graph.microsoft.com`, `management.core.windows.net`, `portal.azure.com`, `login.microsoft.com`, `aadcdn.msauth.net`, `aadcdn.msftauth.net` (Azure CLI)
- `expo.dev`, `api.expo.dev`, `u.expo.dev`, `packages.expo.dev` (Expo/EAS)
- `pypi.org`, `files.pythonhosted.org` (Python packages)

**Also allowed:** DNS (port 53), SSH (port 22), loopback, established connections.

**Everything else on ports 80/443 is dropped.**

To add more domains, edit `init-firewall.sh`:

```bash
ALLOWED_DOMAINS=(
    # ... existing entries ...
    "your-domain.example.com"
)
```

Then rebuild: `docker build -t claude-code-safe .`

### Azure CLI support

Azure CLI authentication and management domains are whitelisted by default. To use the Azure CLI inside the container:

```bash
claude-safe --shell
az login    # Opens browser for authentication
az account show
```

**Azure Storage:** If you need to access Azure Blob Storage, uncomment the storage domains in `init-firewall.sh`:

```bash
# Azure Storage (uncomment if needed for specific storage accounts)
"blob.core.windows.net"
```

Note: Wildcard domains (e.g., `*.blob.core.windows.net`) don't work with the DNS-based firewall. You may need to add specific storage account hostnames (e.g., `mystorageaccount.blob.core.windows.net`) or use `--no-firewall` for sessions requiring extensive Azure Storage access.

The firewall requires `--cap-add=NET_ADMIN --cap-add=NET_RAW`, which the wrapper script adds automatically.

### Expo/EAS CLI support

Expo/EAS domains are whitelisted by default. To use the EAS CLI inside the container:

```bash
claude-safe --expo --shell
eas login
eas build:list
```

### SSH server selection

The `--ssh` flag provides selective SSH credential mounting rather than exposing your entire `~/.ssh` directory:

```bash
# Interactive picker — shows all hosts from ~/.ssh/config
claude-safe --ssh

# Explicit host selection (also works in non-interactive mode)
claude-safe --ssh myserver,github.com
claude-safe --ssh production -p "deploy the release"
```

The picker parses `~/.ssh/config`, displays available Host entries with their HostName and User, and copies only the selected host blocks, their IdentityFile keys, and `known_hosts` to a temporary directory. This temp dir is mounted read-only and cleaned up on exit.

**Note:** `Include` directives in SSH config are not followed — only hosts defined directly in `~/.ssh/config` are available.

### Limitations

The firewall is **DNS-based at startup time** — it resolves whitelisted domains to IPs and creates iptables rules. This means:

- If a domain's IP changes after container start, the new IP is not automatically whitelisted
- DNS-based data exfiltration (encoding data in DNS queries) is not blocked
- Non-HTTP protocols on non-standard ports are not restricted

---

## Security model

### What is isolated

- **Filesystem:** Claude can only see `/workspace` (your mounted project) and its own home directory
- **Processes:** Container PID namespace — Claude cannot see or signal host processes
- **Network:** Firewall restricts outbound to whitelisted domains only (when enabled)
- **Package installs:** Anything Claude installs (npm, pip, apt) stays inside the container and is discarded on exit
- **Destructive commands:** With `CLAUDE_CONTAINER_MODE=1`, commands like `rm -rf /` are contained — they can only affect the container, not the host

### What is NOT isolated

- **Workspace files:** Claude has full read/write access to everything in the mounted project directory
- **`.env` files:** If your project contains `.env` or similar secret files, Claude can read them
- **Git credentials:** If your project has `.git/config` with embedded tokens, Claude can access them
- **Auth tokens:** The `~/.claude` bind mount gives Claude access to your authentication credentials
- **GitHub CLI tokens:** `GH_TOKEN` is passed as an env var if `gh auth token` succeeds on the host
- **SSH keys:** With `--ssh` flag, selected SSH config blocks and keys are mounted read-only
- **Azure credentials:** With `--azure` flag, `~/.azure` is mounted, giving access to Azure CLI tokens
- **Expo credentials:** With `--expo` flag, `~/.expo` is mounted, giving access to EAS CLI tokens
- **DNS exfiltration:** Data could theoretically be encoded in DNS queries (port 53 is open)

---

## Architecture decisions

### Why a standalone Docker image (not devcontainer-per-project)

This design prioritizes **portability and simplicity**. Devcontainer configs are project-specific and clutter each repository with configuration overhead. A single pre-built image that mounts any directory dynamically provides:

- No configuration files committed to projects
- Consistent environment across all workspaces
- Instant setup for new projects (just `cd` and run)
- Single point of maintenance for updates and firewall rules

### Why a Docker volume for credentials (not bind mount)

Following [Anthropic's official devcontainer approach](https://github.com/anthropics/claude-code/tree/main/.devcontainer), credentials are stored in a Docker volume (`claude-code-credentials`). This:
- Works identically on macOS, Linux, and WSL2 (no Keychain extraction needed)
- Avoids bind mount permission issues across platforms
- First run requires in-container OAuth; subsequent runs reuse persisted credentials
- Survives image rebuilds (volume is independent of image lifecycle)

### Why `--dangerously-skip-permissions`

Claude Code normally prompts for approval on every file write, command execution, etc. Inside an isolated container this is unnecessary friction — the container _is_ the sandbox. The wrapper script passes this flag by default. If you want interactive approval, edit the `claude-safe` script and remove it from the `STEPS` array.

### Container mode (`CLAUDE_CONTAINER_MODE=1`)

The wrapper script sets `CLAUDE_CONTAINER_MODE=1` to signal that Claude Code is running inside an isolated container. This relaxes certain safety checks that are redundant when container isolation is already in place.

**Full mode (default, outside containers) blocks:**
- `rm -rf` and dangerous rm patterns
- Fork bombs
- Dangerous git commands (push to main/master, force push)
- Disk write attacks (`dd` to `/dev/`)
- Sensitive file access (`.env`, `.pem`, credentials, etc.)
- Path traversal and project escape

**Container mode blocks only:**
- Dangerous git commands (push to main/master, force push)
- Sensitive file access (`.env`, `.pem`, credentials, etc.)

The rationale: destructive filesystem operations (`rm -rf`, fork bombs, disk attacks) are contained within the ephemeral container and cannot affect the host system beyond the mounted workspace. However, git operations that push to remotes and access to sensitive files remain blocked since those can have effects outside the container.

### Why `node:20-bookworm-slim` as base

Claude Code requires Node.js. The `node:20-bookworm-slim` image provides it without the full Debian install. The `node` user (UID 1000) is pre-created, which matches typical host user UIDs for bind mount permission compatibility.

### Included tools

The image includes common development tools beyond the base Node.js environment:

- **Shell:** zsh with Oh My Zsh (default shell)
- **Version control:** git, GitHub CLI (`gh`)
- **Cloud CLIs:** Azure CLI (`az`), EAS CLI (`eas`)
- **Search:** ripgrep (`rg`), fd (`fdfind`), fzf
- **Utilities:** jq, vim, tmux, curl, wget, ffmpeg
- **Python:** python3, uv, ruff, pip-audit
- **Networking:** iptables, dnsutils (for firewall)

### Environment variables set by the wrapper

| Variable | Value | Purpose |
|---|---|---|
| `CLAUDE_CONFIG_DIR` | `/home/node/.claude` | Auth credential location |
| `CLAUDE_CONTAINER_MODE` | `1` | Relaxes safety checks (see above) |
| `CLAUDE_CODE_ENABLE_RIPGREP` | `0` | Disables startup ripgrep scan to avoid 20s timeout on slow Docker bind mounts ([#7053](https://github.com/anthropics/claude-code/issues/7053)) |
| `CLAUDE_AUDIO_ENABLED` | `1` | Enables audio notifications on events |
| `NODE_OPTIONS` | `--max-old-space-size=4096` | Increases Node.js heap limit |
| `GIT_AUTHOR_NAME` / `GIT_COMMITTER_NAME` | From host `git config` | Git commit identity |
| `GIT_AUTHOR_EMAIL` / `GIT_COMMITTER_EMAIL` | From host `git config` | Git commit email |
| `GH_TOKEN` | From host `gh auth token` | GitHub CLI and git credential authentication |

---

## Troubleshooting

### `Permission denied` running `claude-safe`

```
/usr/local/bin/claude-safe: Permission denied
```

The file needs read+execute permissions. Bash scripts (unlike compiled binaries) must be readable:

```bash
sudo chmod 755 /usr/local/bin/claude-safe
```

If on macOS, also check for quarantine:

```bash
xattr /usr/local/bin/claude-safe
# Remove quarantine if present:
sudo xattr -d com.apple.quarantine /usr/local/bin/claude-safe
```

### `unbound variable` error on EXTRA_ARGS

```
line 140: EXTRA_ARGS[@]: unbound variable
```

This was a bug in an earlier version of the script. `set -u` (strict mode) treats empty bash arrays as unbound. The current script guards against this:

```bash
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    CMD+=("${EXTRA_ARGS[@]}")
fi
```

If you see this error, re-copy the latest `claude-safe` script.

### Build fails with OOM during native installer

```
Killed
```

The native installer has a memory bug when run as root or from a large directory. See [anthropics/claude-code#22536](https://github.com/anthropics/claude-code/issues/22536). The current Dockerfile works around this by running as `USER node` from `/tmp/claude-install`. If you still hit OOM, increase Docker's memory limit in Docker Desktop → Settings → Resources.

### GitHub CLI auth fails inside the container

```
X Failed to log in to github.com account ... The token in default is invalid.
```

Or `git pull` fails with:

```
fatal: could not read Username for 'https://github.com': No such device or address
```

**Cause:** `gh` is either not installed on the host, or not authenticated. The wrapper script runs `gh auth token` on the host to extract the token and passes it into the container as the `GH_TOKEN` environment variable. If this fails, you'll see a warning at startup.

**Fix:**

```bash
gh auth login
```

The token can be stored in the OS keychain (default) or in `hosts.yml` (`--insecure-storage`) — either way, `gh auth token` will extract it.

### Claude asks for `/login` every time

Your `~/.claude` directory on the host is either missing or not being mounted. Verify:

```bash
ls -la ~/.claude/.credentials.json
```

If the file doesn't exist, run `claude-safe --shell` and authenticate inside the container. The credentials should appear on the host afterwards.

### Firewall blocks a domain you need

Edit `init-firewall.sh`, add the domain to `ALLOWED_DOMAINS`, and rebuild:

```bash
docker build -t claude-code-safe .
```

Or skip the firewall for a single session:

```bash
claude-safe --no-firewall
```

### `--rebuild` can't find Dockerfile

The `--rebuild` flag looks for the Dockerfile in `$CLAUDE_SAFE_DIR` (default `$HOME/claude-safe`). If you installed via `install.sh` only, the source isn't on disk — clone it first:

```bash
git clone https://github.com/albertsikkema/claude-safe.git ~/claude-safe
claude-safe --rebuild
```

If your clone lives elsewhere, point `CLAUDE_SAFE_DIR` at it:

```bash
export CLAUDE_SAFE_DIR=/path/to/claude-safe
claude-safe --rebuild
```

Note: most users don't need `--rebuild` at all — `claude-safe --pull` fetches the nightly-built image from GHCR, which is what the auto-update path uses.

---

## Alternatives

### Docker Sandboxes

Docker provides an official sandbox feature (`docker sandbox run claude …`) for running Claude Code in isolation. However, there are some considerations:

- Authentication requires `ANTHROPIC_API_KEY` (Console API credits), not OAuth tokens from Max/Pro subscriptions
- Credentials may not persist between sandbox sessions
- Requires Docker Desktop with sandbox features enabled

For more information, see the [Docker Sandboxes documentation](https://docs.docker.com/ai/sandboxes/claude-code/).

This project takes a different approach: a standard Docker container with bind-mounted credentials, providing better compatibility with Claude Max/Pro subscriptions and full control over the container environment.

---

## Reference links

- [Claude Code setup docs (native installer)](https://code.claude.com/docs/en/setup)
- [Claude Code troubleshooting](https://code.claude.com/docs/en/troubleshooting)
- [Using Claude Code with Max/Pro plan](https://support.claude.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan)
- [Native installer OOM bug — #22536](https://github.com/anthropics/claude-code/issues/22536)
- [npm → native migration conflicts — #7734](https://github.com/anthropics/claude-code/issues/7734)
- [Auto-updater reinstalls npm after native install — #22415](https://github.com/anthropics/claude-code/issues/22415)
