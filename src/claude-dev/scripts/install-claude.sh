#!/usr/bin/env bash
set -euo pipefail

# Install Claude Code with the official native installer, as the remoteUser.
#
# Deliberately NOT the ghcr.io/anthropics/devcontainer-features/claude-code
# Feature: that runs `npm install -g` as root, leaving the global node_modules
# root-owned, so Claude's background auto-updater cannot write and silently
# gives up. Chowning the package directory does not fix it either, because
# `npm install -g` also rewrites node_modules/.package-lock.json, the bin/
# symlinks, and the per-platform optional dependency.
#
# The native installer puts everything under the user's own home:
#   ~/.local/bin/claude          -> symlink managed by the installer
#   ~/.local/share/claude/versions/<version>
# so auto-update works with no privilege games. ~/.local/bin is already on PATH
# in the devcontainer base images.
#
# Idempotent: safe to re-run.

BIN_DIR="${HOME}/.local/bin"

if command -v claude >/dev/null 2>&1; then
  echo "Claude Code already installed: $(claude --version 2>/dev/null || echo unknown)"
else
  echo "Installing Claude Code via the native installer..."
  curl -fsSL https://claude.ai/install.sh | bash
fi

case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *) export PATH="${BIN_DIR}:${PATH}" ;;
esac

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: claude not found on PATH after install." >&2
  exit 1
fi

# A second installation on PATH (e.g. a leftover npm global one) makes it
# ambiguous which binary runs. Surface it rather than let it confuse later.
if [ "$(command -v claude)" != "${BIN_DIR}/claude" ]; then
  echo "WARNING: 'claude' resolves to $(command -v claude), not ${BIN_DIR}/claude." >&2
  echo "  Another installation may be shadowing the native one; run 'claude doctor'." >&2
fi

claude --version
echo "Claude Code install complete."
