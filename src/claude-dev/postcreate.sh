#!/usr/bin/env bash
set -euo pipefail

# Runs once per container creation, as the remoteUser (vscode).
#
# Order is load-bearing:
#   1. claim the ~/.claude volume (Docker creates it root-owned)
#   2. install Claude Code
#   3. seed ~/.claude from the host bind-mount  (ships settings.json)
#   4. enable the rtk hook                      (PATCHES settings.json)
# Steps 3 and 4 must not be swapped: the seed copy would overwrite the file rtk
# just patched, silently removing the hook.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-/home/vscode/.claude}"

echo "=== claude-dev: postCreate starting (CLAUDE_CONFIG_DIR=$CLAUDE_DIR) ==="

# 1. The named volume is mounted root-owned, so take ownership before anything
#    tries to write. chown fails on the bind-mounted .credentials.json nested
#    inside this directory; that is expected and harmless.
sudo mkdir -p "$CLAUDE_DIR"
sudo chown -R "$(id -un):$(id -gn)" "$CLAUDE_DIR" || true

# 2-4
"$SCRIPT_DIR/scripts/install-claude.sh"
"$SCRIPT_DIR/scripts/init-claude-config.sh"
"$SCRIPT_DIR/scripts/install-rtk.sh"

echo "=== claude-dev: postCreate complete ==="
