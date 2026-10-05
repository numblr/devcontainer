#!/usr/bin/env bash
set -euo pipefail

# Seed the per-container ~/.claude volume from the host config bind-mount.
#
# One-time only, guarded by a marker file inside the volume: the volume is keyed
# to ${devcontainerId} and survives rebuilds, so this runs on first create and
# never again. Consequence to be aware of: changes to the host seed do NOT reach
# an existing container until its volume is removed. That is deliberate --
# settings.json is both seed config and where Claude writes in-session
# permission approvals, so a re-sync rule would have to arbitrate between them.

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-/home/vscode/.claude}"
SEED_DIR="/home/vscode/.claude-seed"
MARKER="$CLAUDE_DIR/.initialized-from-seed"

mkdir -p "$CLAUDE_DIR"

# The shared credentials file is bind-mounted from the host. If the host path did
# not exist at create time, Docker silently makes a directory here instead, which
# fails in confusing ways later. Check on every start, not just first init.
# The project's initializeCommand should prevent this; this is the backstop.
CREDS="$CLAUDE_DIR/.credentials.json"
if [ -d "$CREDS" ]; then
  echo "WARNING: $CREDS is a directory, not a file." >&2
  echo "  The host mount source is missing. On the host run:" >&2
  echo "    mkdir -p ~/.claude-devcon-shared && touch ~/.claude-devcon-shared/.credentials.json" >&2
  echo "    chmod 600 ~/.claude-devcon-shared/.credentials.json" >&2
  echo "  then rebuild the container." >&2
fi

if [ -e "$MARKER" ]; then
  echo "Claude config already initialized from seed."
  exit 0
fi

if [ -d "$SEED_DIR" ] && [ "$(find "$SEED_DIR" -mindepth 1 -maxdepth 1 | head -n 1)" ]; then
  echo "Copying Claude seed config into private volume..."
  # .credentials.json is excluded explicitly: it is bind-mounted from the host,
  # so copying a seed file over it would write THROUGH the mount and clobber the
  # real host credentials. The seed is not supposed to contain one, but the
  # tripwire should not exist at all.
  ( cd "$SEED_DIR" && tar --exclude='./.credentials.json' -cf - . ) \
    | ( cd "$CLAUDE_DIR" && tar -xf - )
else
  echo "No Claude seed config found; continuing with empty config."
fi

# chown fails on the bind-mounted credentials file; that is expected and harmless.
sudo chown -R "$(id -un):$(id -gn)" "$CLAUDE_DIR" || true
touch "$MARKER"

echo "Claude config initialized."
