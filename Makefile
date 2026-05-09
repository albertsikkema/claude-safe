PREFIX ?= /usr/local/bin
IMAGE := claude-code-safe
SERVER ?= <your-server>

.PHONY: install install-local install-server build build-local build-server clean-local clean-server cleanup-server help

# Install both scripts to $(PREFIX).
install: install-local install-server

# Build the Docker image locally and on the remote server.
build: build-local build-server

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  install         Install both claude-safe and claude-server to $(PREFIX)"
	@echo "  install-local   Install claude-safe to $(PREFIX)"
	@echo "  install-server  Install claude-server to $(PREFIX)"
	@echo "  build           Build the Docker image locally and on remote server"
	@echo "  build-local     Build the Docker image locally (no cache, latest)"
	@echo "  build-server    Build the Docker image on remote server"
	@echo "  clean-local     Remove the local Docker image"
	@echo "  clean-server    Remove the Docker image on remote server"
	@echo "  cleanup-server  List and remove all sessions on remote server"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX    Installation directory (default: /usr/local/bin)"
	@echo "  SERVER    Remote server for server targets (default: <your-server>)"

install-local:
	sudo cp claude-safe $(PREFIX)/claude-safe
	sudo chmod 755 $(PREFIX)/claude-safe
	@echo "Installed to $(PREFIX)/claude-safe"

install-server:
	sudo cp claude-server $(PREFIX)/claude-server
	sudo chmod 755 $(PREFIX)/claude-server
	@echo "Installed to $(PREFIX)/claude-server"
	@echo ""
	@echo "Set your remote host in your shell profile:"
	@echo "  echo 'export CLAUDE_SERVER_HOST=your-host' >> ~/.zshrc   # zsh"
	@echo "  echo 'export CLAUDE_SERVER_HOST=your-host' >> ~/.bashrc  # bash"

# Build the Docker image locally. Always pulls the latest base image and
# ignores the layer cache to ensure the latest OS packages and Claude Code.
build-local:
	docker build --no-cache --pull -t $(IMAGE) .

# Build the Docker image on the remote server. Syncs the Dockerfile and
# build context, then builds with --no-cache --pull.
build-server:
	./claude-server --rebuild

# Remove the local Docker image. Does not affect credential volumes.
clean-local:
	docker rmi $(IMAGE)

# Guard: ensure SERVER is a real host, not the placeholder default.
check-server:
	@if [ -z "$(SERVER)" ] || [ "$(SERVER)" = "<your-server>" ]; then \
		echo "ERROR: SERVER not set." >&2; \
		echo "  Pass it:   make $(MAKECMDGOALS) SERVER=your-host" >&2; \
		echo "  Or export: export CLAUDE_SERVER_HOST=your-host && make $(MAKECMDGOALS) SERVER=\$$CLAUDE_SERVER_HOST" >&2; \
		exit 1; \
	fi

# Remove the Docker image on the remote server. Does not affect credential volumes.
clean-server: check-server
	ssh $(SERVER) "docker rmi $(IMAGE)"

# List and remove all sessions (containers, workspaces, temp dirs) on the remote server.
cleanup-server: check-server
	CLAUDE_SERVER_HOST=$(SERVER) claude-server --cleanup-all
