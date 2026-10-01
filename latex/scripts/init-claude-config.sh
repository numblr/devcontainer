#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-/home/vscode/.claude}"
SEED_DIR="/home/vscode/.claude-seed"
MARKER="$CLAUDE_DIR/.initialized-from-seed"

mkdir -p "$CLAUDE_DIR"

if [ -e "$MARKER" ]; then
  echo "Claude config already initialized from seed."
  exit 0
fi

if [ -d "$SEED_DIR" ] && [ "$(find "$SEED_DIR" -mindepth 1 -maxdepth 1 | head -n 1)" ]; then
  echo "Copying Claude seed config into private volume..."
  cp -R "$SEED_DIR"/. "$CLAUDE_DIR"/
else
  echo "No Claude seed config found; continuing with empty config."
fi

sudo chown -R vscode:vscode "$CLAUDE_DIR"
touch "$MARKER"

echo "Claude config initialized."
