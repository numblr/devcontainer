#!/usr/bin/env bash
set -e

# Behavioural test for claude-dev, run as remoteUser 'vscode' with a seed
# directory bind-mounted (created by the scenario's initializeCommand).
#
# The credentials bind-mount is deliberately absent: nothing here needs to
# authenticate, and its absence also exercises the "no creds mounted" path.

source dev-container-features-test-lib

CLAUDE_DIR="/home/vscode/.claude"

# --- environment contributed by the feature metadata ---
check "CLAUDE_CONFIG_DIR is set by the feature" \
  bash -c "[ \"\$CLAUDE_CONFIG_DIR\" = '$CLAUDE_DIR' ]"

# --- Claude Code: installed, and installed USER-OWNED ---
check "claude is on PATH" bash -c "command -v claude"
check "claude --version works" bash -c "claude --version"

# The whole reason for dropping the upstream claude-code Feature: a root-owned
# npm global install cannot auto-update. Assert we got the native layout.
check "claude resolves to the user-owned native install" \
  bash -c "[ \"\$(command -v claude)\" = \"\$HOME/.local/bin/claude\" ]"
check "native version dir exists" bash -c "test -d \"\$HOME/.local/share/claude/versions\""
check "claude binary is writable by this user (auto-update can work)" \
  bash -c "test -w \"\$HOME/.local/share/claude\""

# --- seeding ---
check "seed marker written" bash -c "test -f '$CLAUDE_DIR/.initialized-from-seed'"
check "seeded skills copied" bash -c "test -f '$CLAUDE_DIR/skills/example/SKILL.md'"

# --- rtk ---
check "rtk is on PATH" bash -c "command -v rtk"
check "rtk --version works" bash -c "rtk --version"

# THE headline regression: bare `rtk init --global` prompts, postCreate has no
# TTY, so the hook silently never installed in three of the old configs.
check "rtk does NOT report the hook missing" \
  bash -c "! rtk init --show 2>&1 | grep -E '^\[.*\] Hook:' | grep -q 'not found'"
check "settings.json has a hooks key" \
  bash -c "python3 -c \"import json;d=json.load(open('$CLAUDE_DIR/settings.json'));assert 'hooks' in d, d.keys()\""

# Ordering proof: the seed ships settings.json and rtk patches it. If seeding ran
# after rtk the hook would be gone; if rtk clobbered the file the seed's
# permissions would be gone. Both must survive.
check "seeded permissions survived the rtk patch" \
  bash -c "python3 -c \"import json;d=json.load(open('$CLAUDE_DIR/settings.json'));assert 'Read(~/.zshrc)' in d['permissions']['allow'], d\""

check "RTK.md present" bash -c "test -f '$CLAUDE_DIR/RTK.md'"

reportResults
