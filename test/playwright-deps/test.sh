#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

# Default test: runs as root on the base image given to `devcontainer features
# test`. The 'bookworm' scenario covers the pre-t64 distribution generation.
#
# Structure mirrors test/latex/test.sh: the cheap, precise checks that answer
# "is the package list complete?" come first and name the missing thing
# directly, and only then does an end-to-end launch run. Conflating the two is
# what made the latex failure hard to read.

LDCONFIG="$(command -v ldconfig || echo /sbin/ldconfig)"
export LDCONFIG

# --- 1. are the libraries actually on the system? -------------------------
#
# Checked by SONAME, not package name, because the package names differ between
# distribution generations (libasound2 vs libasound2t64) while the sonames do
# not. This is the check that validates pick() in install.sh resolved correctly.
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

# --- 2. Playwright itself, in a venv ---------------------------------------
#
# A venv rather than a bare `pip install`, both to dodge PEP 668
# externally-managed-environment refusals and because it is how a real project
# consumes this: the browser download belongs to the project, not the feature.
check "playwright package installs" bash -c '
  python3 -m venv /tmp/pw-venv &&
  /tmp/pw-venv/bin/pip install --quiet --upgrade pip &&
  /tmp/pw-venv/bin/pip install --quiet playwright &&
  /tmp/pw-venv/bin/playwright --version
'

check "chromium downloads" bash -c '/tmp/pw-venv/bin/playwright install chromium'

# --- 3. nothing chromium links against is unresolved -----------------------
#
# The analogue of the kpsewhich check in the latex test: it names the missing
# .so rather than reporting an opaque launch failure. ldd does not see
# dlopen'd libraries, which is why the real launch below still has to happen.
# Playwright >= 1.49 ships a separate headless shell binary, so check both.
check "no unresolved shared libraries in chromium" bash -c '
  found=0
  missing=""
  while IFS= read -r bin; do
    found=$((found + 1))
    out="$(ldd "$bin" 2>/dev/null | grep "not found" || true)"
    if [ -n "$out" ]; then
      missing="$missing
$bin:
$out"
    fi
  done < <(find "$HOME/.cache/ms-playwright" -type f \( -name chrome -o -name headless_shell \) -perm -u+x 2>/dev/null)

  if [ "$found" -eq 0 ]; then
    echo "no chromium binary found under $HOME/.cache/ms-playwright"
    exit 1
  fi
  if [ -n "$missing" ]; then
    echo "$missing"
    echo "adjust the apt package list in src/playwright-deps/install.sh"
    exit 1
  fi
  echo "$found chromium binary/binaries checked, all libraries resolved"
'

# --- 4. end to end: it launches and actually renders -----------------------
#
# Quoted heredoc. An unquoted one eats the backslashes and collapses the
# content -- exactly the bug that made the latex test fail locally.
cat > /tmp/render_check.py <<'PY'
import os

from playwright.sync_api import sync_playwright

SHOT = "/tmp/playwright-deps-check.png"

# --disable-dev-shm-usage because the container gets the Docker default 64MB
# /dev/shm. The project-level fix is runArgs ["--ipc=host"]; this flag keeps the
# test itself independent of how the test container was run.
with sync_playwright() as p:
    browser = p.chromium.launch(args=["--disable-dev-shm-usage"])
    page = browser.new_page()
    page.set_content("<h1>playwright-deps ok</h1>")
    text = page.inner_text("h1")
    page.screenshot(path=SHOT)
    browser.close()

assert text == "playwright-deps ok", f"unexpected text: {text!r}"

# A launch that renders nothing still produces a valid tiny PNG, so assert the
# screenshot has real content -- this is what catches a missing font or
# graphics library that did not stop the process from starting.
size = os.path.getsize(SHOT)
assert size > 1000, f"screenshot suspiciously small: {size} bytes"

print(f"rendered {text!r}, screenshot {size} bytes")
PY

check "headless chromium launches and renders" /tmp/pw-venv/bin/python /tmp/render_check.py

reportResults
