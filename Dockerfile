# Claude Code safe container image
# Uses native installer (npm is deprecated):
#   https://code.claude.com/docs/en/setup
#
# Image is built nightly in CI and pushed to ghcr.io/albertsikkema/claude-code-safe.
# To build locally for development: docker build -t claude-code-safe .
# Run via the claude-safe / claude-server wrapper scripts.

# Pinned by digest; bump via Renovate/Dependabot or manually:
#   docker buildx imagetools inspect node:24-bookworm-slim
FROM node:24-bookworm-slim@sha256:24dc26ef1e3c3690f27ebc4136c9c186c3133b25563ae4d7f0692e4d1fe5db0e

ENV DEBIAN_FRONTEND=noninteractive

# Single layer: install minimal bootstrap, register gh + Azure CLI repos,
# then install the full toolchain. One apt update per layer instead of three.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gpg \
        lsb-release \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && curl -sLS https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/azure-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends \
        tzdata \
        git \
        wget \
        sudo \
        openssh-client \
        zsh \
        ripgrep \
        fd-find \
        fzf \
        jq \
        less \
        vim \
        nano \
        tmux \
        iptables \
        ipset \
        dnsutils \
        aggregate \
        python3 \
        python-is-python3 \
        ffmpeg \
        file \
        procps \
        python3-venv \
        make \
        gcc \
        libc-dev \
    && apt-get install -y gh azure-cli \
    && rm -rf /var/lib/apt/lists/*

# Install Go
ARG GO_VERSION=1.24.0
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz" \
    | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

# Passwordless sudo for node user (needed for firewall init)
RUN echo "node ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

# Create root-owned dirs before dropping privileges
RUN mkdir -p /commandhistory && chown node:node /commandhistory

# Embed the firewall script
COPY --chmod=755 init-firewall.sh /usr/local/bin/init-firewall.sh

# Global ripgrep config and ignore file to speed up searches
COPY --chmod=644 .rgignore /etc/rgignore
COPY --chmod=644 .ripgreprc /etc/ripgreprc
ENV RIPGREP_CONFIG_PATH=/etc/ripgreprc

# Configure git to use GitHub CLI for HTTPS credential auth
# System-level config so it doesn't conflict with user's mounted ~/.gitconfig
RUN git config --system credential.helper '!/usr/bin/gh auth git-credential'

# Install EAS CLI (Expo Application Services) - must run as root for global npm install
RUN npm install -g eas-cli

# Playwright Chromium system deps (libnss3, libxkbcommon0, etc.) - root + apt-get
RUN npx -y playwright@latest install-deps chromium \
    && rm -rf /var/lib/apt/lists/*

# Switch to non-root user
USER node

# Install Claude Code via native installer (NOT npm)
# OOM workaround: run from /tmp, not a large directory
# Ref: https://github.com/anthropics/claude-code/issues/22536
# Retry loop: installer can 429 under rate limits
RUN mkdir -p /tmp/claude-install && cd /tmp/claude-install \
    && for i in 1 2 3 4 5; do \
         curl -fsSL https://claude.ai/install.sh | bash && break; \
         echo "==> Attempt $i failed, waiting ${i}0s before retry..."; \
         sleep $((i * 10)); \
       done \
    && rm -rf /tmp/claude-install

# Install uv and ruff (Python toolchain)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && /home/node/.local/bin/uv tool install ruff \
    && /home/node/.local/bin/uv tool install pip-audit

# Create pip/pip3 wrappers that delegate to uv pip
# This lets standard "pip install pytest" work inside the container
RUN printf '#!/bin/sh\nif [ -n "$VIRTUAL_ENV" ]; then\n  exec uv pip "$@"\nelse\n  exec uv pip --system "$@"\nfi\n' \
    > /home/node/.local/bin/pip \
    && cp /home/node/.local/bin/pip /home/node/.local/bin/pip3 \
    && chmod +x /home/node/.local/bin/pip /home/node/.local/bin/pip3

# Install chrome-for-testing for Playwright MCP into /home/node/.cache/ms-playwright.
# chrome-for-testing is what @playwright/mcp defaults to; baking it in avoids forcing
# every consumer to add --browser flags to their .mcp.json.
RUN npx -y @playwright/mcp@latest install-browser chrome-for-testing

# Ensure claude and uv/ruff are on PATH
ENV PATH="/home/node/.local/bin:/home/node/go/bin:${PATH}"

# Oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/node/.zshrc

# User-owned dirs and files
RUN mkdir -p /home/node/.claude /home/node/.azure
WORKDIR /workspace
ENV SHELL=/bin/zsh
CMD ["zsh"]
