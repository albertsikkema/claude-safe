# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A standalone Docker image plus two bash wrapper scripts for running Claude Code in isolated containers with a firewall-restricted network. No source code to compile — the "product" is the image definition and the wrappers.

## Components

- `Dockerfile` — builds `claude-code-safe` from `node:20-bookworm-slim`. Installs Claude Code via the **native installer** (not npm — npm is deprecated). Also installs Go, Python (uv/ruff/pip-audit), gh, Azure CLI, EAS CLI, zsh+ohmyzsh, ripgrep/fd/fzf, tmux, iptables. Runs as non-root `node` user (UID 1000).
- `init-firewall.sh` — runs at container startup (via `sudo`) when the firewall is enabled. Resolves a hardcoded `ALLOWED_DOMAINS` list to IPs and installs iptables rules that drop all outbound 80/443 except to those IPs. DNS (53), SSH (22), loopback, and established connections are allowed.
- `claude-safe` — local wrapper. Builds the `docker run` invocation: bind-mounts the target dir to `/workspace`, mounts the `claude-code-credentials` Docker volume at `/home/node/.claude`, wires up optional SSH/Azure/Expo/GitHub credential mounts, extracts `GH_TOKEN` from host `gh auth token`, sets env vars, and by default passes `--dangerously-skip-permissions` to `claude`.
- `claude-server` — remote wrapper. Same shape as `claude-safe` but rsyncs the workspace to `$CLAUDE_SERVER_HOST` (default `<your-server>`), runs the container there (detached for `-p`, wrapped in tmux for interactive), and syncs results back on `--sync`. Session state lives under `~/claude-server/<session-id>/` on the remote.
- `Makefile` — `build-local`, `build-server`, `install-local`, `install-server`, `clean-local`, `clean-server`, `cleanup-server`.

## Common commands

```bash
make build-local              # docker build --no-cache --pull -t claude-code-safe .
make install-local            # sudo cp claude-safe /usr/local/bin/ && chmod 755
make install-server           # same for claude-server
make build                    # build-local + build-server
make clean-local              # docker rmi claude-code-safe

claude-safe --rebuild         # full rebuild from within the wrapper
claude-safe --shell           # drop into zsh in the container (used for first-run OAuth)
claude-server --rebuild       # rebuild image on the remote server
claude-server --cleanup-all   # wipe all remote sessions
```

There are no tests, linters, or CI. Validation is manual: rebuild the image, run `claude-safe --shell`, exercise the change.

## Editing rules specific to this repo

- **Firewall changes go in `init-firewall.sh`**, in the `ALLOWED_DOMAINS` array. The firewall is DNS-based at startup — wildcards do not work, add concrete hostnames. After editing, rebuild the image.
- **Wrapper flag parity.** `claude-safe` and `claude-server` share most flags (`--shell`, `--ssh`, `--azure`, `--expo`, `--no-firewall`, `--update`, `--rebuild`, pass-through `-p`/`--model`/`--output-format`/`--verbose`/`--max-turns`, and `--` for extra claude args). When adding or changing a flag in one, mirror it in the other unless the flag is inherently local- or server-only.
- **Credential volume is sacred.** `claude-code-credentials` (Docker volume) holds the OAuth token. Never bind-mount `~/.claude` over it, never delete it in cleanup targets, and do not add logic that recreates it on each run.
- **Native installer OOM workaround.** The `claude.ai/install.sh` step runs as `USER node` from `/tmp/claude-install` to avoid [#22536](https://github.com/anthropics/claude-code/issues/22536). Do not "simplify" this back to a single-line `curl | bash` as root.
- **`CLAUDE_CONTAINER_MODE=1`** is set by the wrappers to tell Claude Code it is sandboxed. This intentionally relaxes destructive-command blocks (rm -rf, fork bombs) while keeping git-push-to-main and sensitive-file blocks active. Don't unset it in the wrappers.
- **`--dangerously-skip-permissions`** is passed by default because the container is the sandbox. Leave it unless you're explicitly building a non-sandboxed mode.
- **GH token passthrough.** The wrapper runs `gh auth token` on the host and forwards it as `GH_TOKEN`. If `gh` is missing or logged out, print a warning but do not fail — the container is still usable.
- **No AI-attribution markers anywhere.** See `.claude/rules/claude-settings.md`. No `Co-Authored-By`, no "Generated with Claude Code" footers, no AI markers in commits, PR titles/bodies, code comments, or docs.
- **Conventional commits, imperative subject, ≤50 chars, no period.** See `.claude/rules/commits.md`. Never commit on `main` — create `feat/…`, `fix/…`, `refactor/…`, or `chore/…` first (`.claude/rules/branching.md`).

## Things to know before debugging

- Bash scripts run under `set -u`. Empty arrays must be guarded with `${#ARR[@]} -gt 0` before expansion, or `set -u` will abort. This has bitten the project before (see README troubleshooting for `EXTRA_ARGS`).
- `CLAUDE_SAFE_DIR` env var controls where `--rebuild` looks for the `Dockerfile`/build context; there is a hardcoded fallback inside `claude-safe`.
- `claude-server` sessions are identified by a session-id directory on the remote under `~/claude-server/`. `--status`, `--logs`, `--attach`, `--sync`, `--stop`, `--cleanup` all key off that id.
- `.claude/` contains extensive project rules (engineering principles, caveman output style, MCP server usage, plan-mode methodology). They apply — read the relevant rule file before doing non-trivial work.
