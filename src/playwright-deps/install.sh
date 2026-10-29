#!/usr/bin/env bash
set -euo pipefail

# System libraries and fonts required by Playwright's headless Chromium.
#
# Runs as ROOT at image build time, so no sudo and the ~200MB result lands in a
# cached image layer instead of being reinstalled on every container create.
#
# Idempotent: safe to re-run (guarded by a marker; there is no binary to probe
# for, unlike src/latex/install.sh which checks for pdflatex).
#
# WHAT THIS DELIBERATELY DOES NOT DO: install Playwright, or a browser. Two
# independent reasons, either one sufficient:
#   - Feature lifecycle hooks run BEFORE the project's postCreateCommand, so at
#     this point the project's venv does not exist and `playwright` is not
#     importable.
#   - Playwright pins an exact browser revision to the installed `playwright`
#     version and refuses any other build, so a pre-baked browser would be the
#     wrong revision for most projects and get re-downloaded anyway.
# The project runs `playwright install chromium` itself.
#
# WHY THIS FEATURE EXISTS AT ALL: `playwright install-deps` has no entry for
# Debian 13, and the names it would use for Debian 12 do not resolve there --
# the 64-bit time_t transition renamed six of these packages in Debian 13 and
# Ubuntu 24.04.
#
# Hence pick() below rather than a hardcoded list. Not hypothetical: the
# floating mcr devcontainers/python tags move across Debian releases on their
# own (python:3.10 is labelled dev.containers.variant=3.10-trixie today), so any
# project pinning only a Python minor can change generation under you on a
# rebuild, in either direction.

MARKER_DIR="/usr/local/share/playwright-deps"
MARKER="$MARKER_DIR/.installed"

if [ -e "$MARKER" ]; then
  echo "playwright-deps: already installed ($(cat "$MARKER"))"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

echo "Installing Playwright headless Chromium system dependencies..."
apt-get update

# First name that actually exists on this distribution. Fails loudly rather than
# silently dropping a library, which would surface much later as an unreadable
# "error while loading shared libraries" when chromium launches.
#
# Deliberately no pipeline. The obvious `apt-cache policy "$n" | grep -q ...`
# is broken under `set -o pipefail`: grep -q exits at its first match and closes
# the pipe, apt-cache then dies of SIGPIPE (141), and pipefail reports the whole
# pipeline as failed even though the package WAS found. That inverts every
# lookup, so pick() falls through to the error and aborts the image build.
pick() {
  local n out
  for n in "$@"; do
    out="$(apt-cache policy "$n" 2>/dev/null || true)"
    case "$out" in
      *"Candidate: (none)"*) ;;          # known to apt, but not installable
      *"Candidate: "*) printf '%s' "$n"; return 0 ;;
    esac
  done
  echo "ERROR: none of these packages exist on this distribution: $*" >&2
  return 1
}

# The six renamed by the time_t transition. Resolved one per line so that
# `set -e` aborts on the exact one that could not be found.
PKG_ASOUND="$(pick libasound2t64 libasound2)"
PKG_ATK="$(pick libatk1.0-0t64 libatk1.0-0)"
PKG_ATK_BRIDGE="$(pick libatk-bridge2.0-0t64 libatk-bridge2.0-0)"
PKG_ATSPI="$(pick libatspi2.0-0t64 libatspi2.0-0)"
PKG_CUPS="$(pick libcups2t64 libcups2)"
PKG_GLIB="$(pick libglib2.0-0t64 libglib2.0-0)"

apt-get install -y --no-install-recommends \
  "$PKG_ASOUND" \
  "$PKG_ATK" \
  "$PKG_ATK_BRIDGE" \
  "$PKG_ATSPI" \
  "$PKG_CUPS" \
  "$PKG_GLIB" \
  libcairo2 \
  libdbus-1-3 \
  libdrm2 \
  libexpat1 \
  libgbm1 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libx11-6 \
  libxcb1 \
  libxcomposite1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxkbcommon0 \
  libxrandr2 \
  fonts-liberation \
  fonts-noto-color-emoji

rm -rf /var/lib/apt/lists/*

# Chromium only. Firefox and WebKit need a largely disjoint library set and
# WebKit's arm64 support is the weakest of the three; adding them later is an
# edit to the list above. No xvfb either -- headless only.

install -d -m 0755 "$MARKER_DIR"
date -u +'%Y-%m-%dT%H:%M:%SZ' > "$MARKER"

echo "playwright-deps: install complete. Run 'playwright install chromium' in the project."
