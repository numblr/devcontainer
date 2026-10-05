#!/usr/bin/env bash
set -e

# Default (auto-detected) test. The harness generates its own devcontainer.json
# here and does not set remoteUser, so this container may run as root with
# HOME=/root while the feature pins CLAUDE_CONFIG_DIR=/home/vscode/.claude.
#
# That mismatch is expected: the feature documents an assumption of
# remoteUser 'vscode'. So this test only asserts what is user-independent --
# that the feature staged its scripts and applied its metadata. The behavioural
# assertions live in the 'seeded' scenario, which sets remoteUser explicitly.

source dev-container-features-test-lib

SHARE_DIR="/usr/local/share/claude-dev"

check "postcreate.sh staged and executable" bash -c "test -x '$SHARE_DIR/postcreate.sh'"
check "install-claude.sh staged and executable" bash -c "test -x '$SHARE_DIR/scripts/install-claude.sh'"
check "init-claude-config.sh staged and executable" bash -c "test -x '$SHARE_DIR/scripts/init-claude-config.sh'"
check "install-rtk.sh staged and executable" bash -c "test -x '$SHARE_DIR/scripts/install-rtk.sh'"

check "CLAUDE_CONFIG_DIR contributed by feature metadata" \
  bash -c "[ -n \"\$CLAUDE_CONFIG_DIR\" ]"

# Guard the ordering constraint at the source level: if someone reorders these
# calls in postcreate.sh, the rtk hook gets silently wiped by the seed copy.
check "postcreate.sh seeds config BEFORE installing rtk" \
  bash -c "awk '/init-claude-config.sh/{s=NR} /install-rtk.sh/{r=NR} END{exit !(s && r && s < r)}' '$SHARE_DIR/postcreate.sh'"

reportResults
