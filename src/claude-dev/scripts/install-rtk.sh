#!/usr/bin/env bash
set -euo pipefail

# Install rtk (Rust Token Killer, rtk-ai/rtk) for the remoteUser and enable the
# Claude Code hook so commands are transparently proxied through rtk.
#
# MUST run AFTER init-claude-config.sh: `rtk init` patches settings.json, and the
# seed also ships a settings.json. Seeding afterwards would overwrite the patch
# and silently remove the hook.
#
# --auto-patch is REQUIRED here, not optional. Bare `rtk init --global` PROMPTS
# before patching settings.json; postCreateCommand has no TTY, so the prompt is
# never answered and the hook is silently never installed. --auto-patch means
# "same as -g, but no prompt".
#
# Docs: https://www.rtk-ai.app/docs/getting-started/installation/
# NOTE: this installs rtk-ai/rtk (Rust Token Killer), NOT the unrelated
# Rust Type Kit that shares the name.

BIN_DIR="${HOME}/.local/bin"

if command -v rtk >/dev/null 2>&1; then
  echo "rtk already installed: $(rtk --version)"
else
  echo "Installing rtk from the official installer..."
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh
fi

# Ensure ~/.local/bin is on PATH for the remaining steps of this script.
case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *) export PATH="${BIN_DIR}:${PATH}" ;;
esac

if ! command -v rtk >/dev/null 2>&1; then
  echo "ERROR: rtk not found on PATH after install." >&2
  exit 1
fi

# Not wrapped in `|| true`: a failure here used to be swallowed, which is how
# three of the old configs shipped without a working hook for months.
echo "Enabling rtk Claude Code hook (rtk init -g --auto-patch)..."
rtk init -g --auto-patch

# Verify rather than assume. Only warns when rtk itself reports the hook
# missing, so a change in rtk's output format cannot produce a false alarm.
if rtk init --show 2>&1 | grep -E '^\[.*\] Hook:' | grep -q 'not found'; then
  echo "WARNING: rtk reports the hook is still not configured." >&2
  echo "  Run 'rtk init --show' in the container to inspect, then" >&2
  echo "  'rtk init -g --auto-patch' to retry." >&2
else
  echo "rtk hook verified present."
fi

rtk --version
echo "rtk install complete."
