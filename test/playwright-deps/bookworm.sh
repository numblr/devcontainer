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
# This image also happens to carry a third-party apt source whose signing key
# is no longer in its keyring (yarn, NO_PUBKEY 62D54FD4003F6525), so a strict
# `apt-get update` exits 100 on it. That is worth keeping rather than avoiding:
# it is exactly the state of an older project pinned to an older image, and it
# means this scenario also covers install.sh tolerating a broken source it does
# not need.
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

# Asserts on what is INSTALLED, via dpkg, not on what apt reports as available:
# install.sh deletes /var/lib/apt/lists, so an apt-cache-based check would find
# no candidate for anything and pass vacuously, silently testing nothing.
check "image is pre-t64 and install.sh resolved the old names" bash -c '
  is_installed() {
    case "$(dpkg-query -s "$1" 2>/dev/null || true)" in
      *"Status: install ok installed"*) return 0 ;;
    esac
    return 1
  }

  . /etc/os-release
  echo "image is $PRETTY_NAME"

  if is_installed libasound2t64; then
    echo "libasound2t64 is installed, so this image is NOT pre-t64."
    echo "  This scenario no longer exercises the fallback path in"
    echo "  src/playwright-deps/install.sh. Pin an older image in"
    echo "  test/playwright-deps/scenarios.json."
    exit 1
  fi

  if ! is_installed libasound2; then
    echo "neither libasound2 nor libasound2t64 is installed."
    echo "  install.sh did not resolve this package at all."
    exit 1
  fi

  echo "confirmed pre-t64: install.sh resolved libasound2, not libasound2t64"
'

check "all chromium sonames resolve" bash -c '
  cache="$("$LDCONFIG" -p)"
  missing=""
  for lib in \
    libasound.so.2 libatk-1.0.so.0 libatk-bridge-2.0.so.0 libatspi.so.0 \
    libcups.so.2 libglib-2.0.so.0 libcairo.so.2 libdbus-1.so.3 libdrm.so.2 \
    libexpat.so.1 libgbm.so.1 libnspr4.so libnss3.so libpango-1.0.so.0 \
    libX11.so.6 libxcb.so.1 libXcomposite.so.1 libXdamage.so.1 libXext.so.6 \
    libXfixes.so.3 libxkbcommon.so.0 libXrandr.so.2
  do
    case "$cache" in
      *"$lib"*) ;;
      *) missing="$missing $lib" ;;
    esac
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
