#!/bin/bash
# Network firewall for Claude Code container
# Based on: https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh
set -euo pipefail

echo "==> Initializing firewall..."

# Flush existing rules
iptables -F OUTPUT 2>/dev/null || true
iptables -F INPUT  2>/dev/null || true

# Destroy existing ipset if present
ipset destroy allowed-ips 2>/dev/null || true

# Create ipset for efficient IP matching (hash:net supports CIDR notation)
ipset create allowed-ips hash:net

# Allow loopback and established connections
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS + SSH always allowed
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# ── GitHub: Fetch official CIDR ranges from API ──────────────────────
# More reliable than DNS resolution - these are GitHub's official IP ranges
echo "    Fetching GitHub IP ranges..."
GITHUB_META=$(curl -s https://api.github.com/meta 2>/dev/null || echo "{}")

if [[ -n "$GITHUB_META" && "$GITHUB_META" != "{}" ]]; then
    # Extract all relevant IP ranges and aggregate them
    GITHUB_CIDRS=$(echo "$GITHUB_META" | jq -r '
        .web[]?,
        .api[]?,
        .git[]?,
        .packages[]?,
        .pages[]?,
        .actions[]?
    ' 2>/dev/null | grep -v ':' | sort -u | aggregate -q 2>/dev/null || true)

    for cidr in $GITHUB_CIDRS; do
        ipset add allowed-ips "$cidr" 2>/dev/null || true
    done
    echo "    Added $(echo "$GITHUB_CIDRS" | wc -w | tr -d ' ') GitHub CIDR ranges"
else
    echo "    WARNING: Could not fetch GitHub IP ranges, falling back to DNS"
    for domain in github.com api.github.com raw.githubusercontent.com objects.githubusercontent.com; do
        for ip in $(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true); do
            ipset add allowed-ips "$ip" 2>/dev/null || true
        done
    done
fi

# ── Other domains: Resolve via DNS ───────────────────────────────────
ALLOWED_DOMAINS=(
    # Anthropic / Claude
    "api.anthropic.com"
    "auth.anthropic.com"
    "console.anthropic.com"
    "claude.ai"
    "statsig.anthropic.com"
    "sentry.io"
    # npm
    "registry.npmjs.org"
    # Azure CLI
    "login.microsoftonline.com"
    "management.azure.com"
    "graph.microsoft.com"
    "management.core.windows.net"
    "portal.azure.com"
    "login.microsoft.com"
    "aadcdn.msauth.net"
    "aadcdn.msftauth.net"
    # Expo / EAS
    "expo.dev"
    "api.expo.dev"
    "u.expo.dev"
    "packages.expo.dev"
    # Python (PyPI)
    "pypi.org"
    "files.pythonhosted.org"
    # Logbench / Axiom
    "api.axiom.co"
    "api.eu.axiom.co"
    # Atlassian (mcp-atlassian)
    "api.atlassian.com"
    "id.atlassian.com"
)

# Append tenant host from JIRA_URL if provided (e.g. mycorp.atlassian.net).
# Firewall is DNS-based and wildcards don't work — add the concrete host.
if [[ -n "${JIRA_URL:-}" ]]; then
    jira_host=$(echo "$JIRA_URL" | sed -E 's#^https?://##; s#/.*$##; s#:.*$##')
    if [[ -n "$jira_host" ]]; then
        ALLOWED_DOMAINS+=("$jira_host")
    fi
fi

echo "    Resolving ${#ALLOWED_DOMAINS[@]} domains..."
for domain in "${ALLOWED_DOMAINS[@]}"; do
    ips=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true)
    for ip in $ips; do
        ipset add allowed-ips "$ip" 2>/dev/null || true
    done
done

# ── Apply rules using ipset ──────────────────────────────────────────
# Allow HTTP/HTTPS to any IP in the allowed set
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed-ips dst -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80  -m set --match-set allowed-ips dst -j ACCEPT

# Drop all other HTTP/HTTPS traffic
iptables -A OUTPUT -p tcp --dport 80  -j DROP
iptables -A OUTPUT -p tcp --dport 443 -j DROP

# ── Verification ─────────────────────────────────────────────────────
echo "    Verifying firewall..."
if curl -s --connect-timeout 2 https://example.com >/dev/null 2>&1; then
    echo "    WARNING: Firewall verification failed - example.com is reachable"
else
    echo "    OK: Blocked traffic verified (example.com unreachable)"
fi

if curl -s --connect-timeout 2 https://api.github.com >/dev/null 2>&1; then
    echo "    OK: Allowed traffic verified (api.github.com reachable)"
else
    echo "    WARNING: api.github.com not reachable - GitHub access may be broken"
fi

IPSET_COUNT=$(ipset list allowed-ips 2>/dev/null | grep -c "^[0-9]" || echo "0")
echo "==> Firewall active. $IPSET_COUNT IPs/CIDRs in allowlist."
