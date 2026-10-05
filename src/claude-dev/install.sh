#!/usr/bin/env bash
set -euo pipefail

# Feature install step. Runs as ROOT at image build time.
#
# It only stages the lifecycle scripts; nothing user-specific happens here.
# The real work runs later from postcreate.sh as the remoteUser (vscode), because:
#   - Claude Code must be installed user-owned for background auto-update to work.
#   - The ~/.claude volume and the host bind-mounts do not exist until the
#     container is created, so seeding cannot happen at build time.

SHARE_DIR="/usr/local/share/claude-dev"

install -d -m 0755 "$SHARE_DIR"
install -m 0755 "$(dirname "$0")/postcreate.sh" "$SHARE_DIR/postcreate.sh"

install -d -m 0755 "$SHARE_DIR/scripts"
for f in "$(dirname "$0")"/scripts/*.sh; do
  install -m 0755 "$f" "$SHARE_DIR/scripts/$(basename "$f")"
done

echo "claude-dev: staged lifecycle scripts in $SHARE_DIR"
