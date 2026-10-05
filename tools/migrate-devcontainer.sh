#!/usr/bin/env bash
set -euo pipefail

# Convert a project's .devcontainer/devcontainer.json from the old copied-folder
# layout to the claude-dev feature.
#
# Run this ON THE HOST -- projects are not reachable from inside the
# devcontainer container.
#
# Dry run by default: prints the proposed file and exits. Pass --write to apply.
#
#   tools/migrate-devcontainer.sh --owner myuser ~/projects/foo
#   tools/migrate-devcontainer.sh --owner myuser --write ~/projects/foo
#
# What it preserves: the base image, and any features that are not part of the
# Claude setup (docker-in-docker, node, ...).
# What it drops: postCreateCommand, containerEnv, the ~/.claude volume mount,
# and the anthropics/claude-code feature -- all now owned by claude-dev.
#
# COMMENTS ARE NOT PRESERVED (devcontainer.json is JSONC; round-tripping
# comments reliably is not worth the complexity). The script warns when the
# original had comments and always writes a backup, so you can paste them back.

OWNER=""
WRITE=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --owner) OWNER="${2:-}"; shift 2 ;;
    --write) WRITE=1; shift ;;
    -h|--help) sed -n '3,25p' "$0"; exit 0 ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

[ -n "$OWNER" ]  || { echo "ERROR: --owner <github-user-or-org> is required." >&2; exit 2; }
[ -n "$TARGET" ] || { echo "ERROR: give a project directory." >&2; exit 2; }

CFG="$TARGET/.devcontainer/devcontainer.json"
[ -f "$CFG" ] || { echo "ERROR: $CFG not found." >&2; exit 1; }

NEW="$(OWNER="$OWNER" python3 - "$CFG" <<'PY'
import json, os, re, sys

path = sys.argv[1]
owner = os.environ["OWNER"]
raw = open(path).read()

# Strip // comments (naively, but only outside strings) to parse the JSONC.
def strip_comments(s):
    out, in_str, esc, i = [], False, False, 0
    while i < len(s):
        c = s[i]
        if in_str:
            out.append(c)
            if esc:            esc = False
            elif c == '\\':    esc = True
            elif c == '"':     in_str = False
        else:
            if c == '"':
                in_str = True; out.append(c)
            elif c == '/' and i + 1 < len(s) and s[i+1] == '/':
                while i < len(s) and s[i] != '\n': i += 1
                continue
            else:
                out.append(c)
        i += 1
    return ''.join(out)

had_comments = bool(re.search(r'(?m)^\s*//', raw))
# Trailing commas are legal in JSONC but not JSON.
cleaned = re.sub(r',(\s*[}\]])', r'\1', strip_comments(raw))
try:
    old = json.loads(cleaned)
except Exception as e:
    print(f"PARSE_ERROR::{e}", file=sys.stderr); sys.exit(3)

# Features owned by claude-dev now, or replaced by it.
DROP = ("anthropics/devcontainer-features/claude-code",)
kept = {}
for fid, opts in (old.get("features") or {}).items():
    if any(d in fid for d in DROP):
        continue
    kept[fid] = opts
kept[f"ghcr.io/{owner}/features/claude-dev:1"] = {}

new = {
    "name": old.get("name", "${localWorkspaceFolderBasename}"),
    "image": old.get("image", "mcr.microsoft.com/devcontainers/python:3.12"),
    "features": kept,
    "remoteUser": old.get("remoteUser", "vscode"),
    "initializeCommand": (
        "mkdir -p ~/.claude-devcon-config ~/.claude-devcon-shared "
        "&& touch ~/.claude-devcon-shared/.credentials.json"
    ),
    "mounts": [
        "source=${localEnv:HOME}/.claude-devcon-config,"
        "target=/home/vscode/.claude-seed,type=bind,readonly",
        "source=${localEnv:HOME}/.claude-devcon-shared/.credentials.json,"
        "target=/home/vscode/.claude/.credentials.json,type=bind",
    ],
}

# Carry over anything we do not recognise, so nothing is silently lost.
HANDLED = {"name", "image", "features", "remoteUser", "mounts", "containerEnv",
           "postCreateCommand", "initializeCommand"}
extra = {k: v for k, v in old.items() if k not in HANDLED}
new.update(extra)

if "Dockerfile" in raw or "build" in old:
    print("WARN::project uses a Dockerfile/build; review the generated 'image' key by hand", file=sys.stderr)
if had_comments:
    print("WARN::original had // comments; they are NOT carried over (see the backup)", file=sys.stderr)
if extra:
    print(f"WARN::carried over unrecognised keys verbatim: {sorted(extra)}", file=sys.stderr)

print(json.dumps(new, indent=2))
PY
)" || { echo "ERROR: could not transform $CFG (see message above)." >&2; exit 1; }

echo "=== proposed $CFG ==="
printf '%s\n' "$NEW"
echo "====================="

SCRIPTS_DIR="$TARGET/.devcontainer/scripts"
KNOWN="init-claude-config.sh install-rtk.sh install-latex.sh"
removable=0
if [ -d "$SCRIPTS_DIR" ]; then
  unknown=""
  for f in "$SCRIPTS_DIR"/*; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    case " $KNOWN " in *" $b "*) ;; *) unknown="$unknown $b" ;; esac
  done
  if [ -n "$unknown" ]; then
    echo "NOTE: keeping $SCRIPTS_DIR -- contains unrecognised files:$unknown" >&2
  else
    removable=1
    echo "NOTE: $SCRIPTS_DIR holds only known old scripts and will be removed."
  fi
fi

if [ "$WRITE" -eq 0 ]; then
  echo
  echo "Dry run. Re-run with --write to apply."
  exit 0
fi

BACKUP="$CFG.bak-$(date +%Y%m%d%H%M%S)"
cp "$CFG" "$BACKUP"
printf '%s\n' "$NEW" > "$CFG"
echo "Wrote $CFG (backup: $BACKUP)"

if [ "$removable" -eq 1 ]; then
  rm -rf "$SCRIPTS_DIR"
  echo "Removed $SCRIPTS_DIR"
fi

echo
echo "Next: rebuild the container, then verify with"
echo "  rtk init --show     # expect Hook: ok, not 'not found'"
echo "  claude doctor"
