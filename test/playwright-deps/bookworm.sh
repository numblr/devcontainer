#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

# Regression guard for the 64-bit time_t package rename.
#
# Bookworm predates that transition, so install.sh must resolve the OLD names
# (libasound2, libatk1.0-0, ...) here while resolving the t64 ones on the
# trixie-based image that test.sh runs against.
#
# The image is pinned to an EXPLICIT suite (1-3.10-bookworm), not a floating
# tag. mcr's floating devcontainers/python:3.10 is labelled
# dev.containers.variant=3.10-trixie, i.e. it has already moved to trixie and
# would prove nothing here -- which is exactly why the first check below exists.
#
# Deliberately lighter than test.sh: this scenario exists to prove name
# resolution and installation, not rendering. Re-downloading ~170MB of chromium
# on a second image would roughly double CI time to re-test what test.sh
# already covers.
#
# Self-contained rather than sourcing shared helpers from test.sh, because the
# test harness's handling of extra files in the test directory is not something
# this repo should depend on.

LDCONFIG="$(command -v ldconfig || echo /sbin/ldconfig)"
export LDCONFIG

check "distribution is pre-t64 (otherwise this scenario proves nothing)" bash -c '
  . /etc/os-release
  echo "image is $PRETTY_NAME"
  if apt-cache policy libasound2t64 2>/dev/null | grep -q "Candidate: [^(]"; then
    echo "WARNING: libasound2t64 exists here, so this image is NOT pre-t64."
    echo "  The t64 fallback path in src/playwright-deps/install.sh is no longer"
    echo "  being exercised -- pin an older image in test/playwright-deps/scenarios.json."
    exit 1
  fi
  echo "confirmed pre-t64: libasound2t64 does not exist on this distribution"
'

check "all chromium sonames resolve" bash -c '
  missing=""
  for lib in \
    libasound.so.2 libatk-1.0.so.0 libatk-bridge-2.0.so.0 libatspi.so.0 \
    libcups.so.2 libglib-2.0.so.0 libcairo.so.2 libdbus-1.so.3 libdrm.so.2 \
    libexpat.so.1 libgbm.so.1 libnspr4.so libnss3.so libpango-1.0.so.0 \
    libX11.so.6 libxcb.so.1 libXcomposite.so.1 libXdamage.so.1 libXext.so.6 \
    libXfixes.so.3 libxkbcommon.so.0 libXrandr.so.2
  do
    "$LDCONFIG" -p | grep -q "$lib" || missing="$missing $lib"
  done
  if [ -n "$missing" ]; then
    echo "missing shared libraries:$missing"
    echo "adjust the apt package list in src/playwright-deps/install.sh"
    exit 1
  fi
  echo "all sonames present"
'

check "liberation fonts installed" bash -c '
  ls /usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf
'

reportResults
