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
#   tools/migrate-devcontainer.sh --owner myuser --playwright --write ~/projects/web
#
# What it preserves: the base image, and any features that are not part of the
# Claude setup (docker-in-docker, node, ...).
# What it drops: postCreateCommand, containerEnv, the ~/.claude volume mount,
# and the anthropics/claude-code feature -- all now owned by claude-dev.
#
# --playwright  also add the playwright-deps feature, merge "--ipc=host" into
#               runArgs and append "playwright install chromium" to
#               postCreateCommand. Opt-in on purpose: no old config implies a
#               browser, so doing it by default would hand every migrated
#               project a capability it never had, at +37 apt packages and
#               ~200MB per image. Without the flag the script still prints a
#               NOTE when the project looks like a frontend, so the reminder
#               arrives where you would otherwise forget it.
#
# COMMENTS ARE NOT PRESERVED (devcontainer.json is JSONC; round-tripping
# comments reliably is not worth the complexity). The script warns when the
# original had comments and always writes a backup, so you can paste them back.

OWNER=""
WRITE=0
PLAYWRIGHT=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --owner) OWNER="${2:-}"; shift 2 ;;
    --write) WRITE=1; shift ;;
    --playwright) PLAYWRIGHT=1; shift ;;
    -h|--help) sed -n '3,34p' "$0"; exit 0 ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

[ -n "$OWNER" ]  || { echo "ERROR: --owner <github-user-or-org> is required." >&2; exit 2; }
[ -n "$TARGET" ] || { echo "ERROR: give a project directory." >&2; exit 2; }

CFG="$TARGET/.devcontainer/devcontainer.json"
[ -f "$CFG" ] || { echo "ERROR: $CFG not found." >&2; exit 1; }

NEW="$(OWNER="$OWNER" PLAYWRIGHT="$PLAYWRIGHT" python3 - "$CFG" "$TARGET" <<'PY'
import json, os, re, sys

path = sys.argv[1]
project = sys.argv[2]
owner = os.environ["OWNER"]
want_pw = os.environ.get("PLAYWRIGHT") == "1"
raw = open(path).read()


def frontend_evidence(root):
    """Cheap signals that a project has a browser-testable frontend.

    Only used to advise. Deciding this automatically is what --playwright is
    for: detection is a guess, and a wrong guess silently fattens an image.
    """
    found = []
    pkg = os.path.join(root, "package.json")
    if os.path.isfile(pkg):
        try:
            txt = open(pkg, encoding="utf-8", errors="replace").read()
        except OSError:
            txt = ""
        for dep in ("@playwright/test", "vite", "next", "react", "vue",
                    "svelte", "@angular/core"):
            if '"%s"' % dep in txt:
                found.append("%s in package.json" % dep)
    for cfg in ("playwright.config.ts", "playwright.config.js",
                "playwright.config.py"):
        if os.path.isfile(os.path.join(root, cfg)):
            found.append(cfg)
    for req in ("pyproject.toml", "requirements.txt", "requirements-dev.txt"):
        f = os.path.join(root, req)
        if not os.path.isfile(f):
            continue
        try:
            txt = open(f, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if "pytest-playwright" in txt or re.search(r'(?m)^\s*playwright\b', txt):
            found.append("playwright in %s" % req)
    for d in ("e2e", os.path.join("tests", "e2e")):
        if os.path.isdir(os.path.join(root, d)):
            found.append("%s/ directory" % d)
    return found

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

# Classify every segment of the old postCreateCommand instead of discarding the
# whole string. Anything that is not recognised Claude/rtk boilerplate is either
# translated to a feature (LaTeX) or preserved verbatim -- otherwise a project
# that did real work in postCreateCommand would lose it silently.
CLAUDE_BOILERPLATE = (
    "init-claude-config.sh",
    "install-rtk.sh",
    "mkdir -p /home/vscode/.claude",
    "chown -R vscode:vscode /home/vscode/.claude",
    "@anthropic-ai",            # the old npm-global chown
)
needs_latex, leftover = False, []
pcc = old.get("postCreateCommand") or ""
if isinstance(pcc, str) and pcc.strip():
    for seg in pcc.split("&&"):
        seg = seg.strip().strip("{}").strip().rstrip(";").strip()
        if not seg:
            continue
        if "install-latex.sh" in seg:
            needs_latex = True
        elif any(b in seg for b in CLAUDE_BOILERPLATE):
            continue
        else:
            leftover.append(seg)
elif pcc:
    print(f"WARN::postCreateCommand is not a plain string ({type(pcc).__name__}); "
          "preserved verbatim, review it by hand", file=sys.stderr)
    leftover = None  # signal: copy as-is

if needs_latex:
    kept[f"ghcr.io/{owner}/features/latex:1"] = {}
    print("NOTE::old postCreateCommand ran install-latex.sh -> added the latex feature", file=sys.stderr)

# --playwright: three coordinated edits. The feature alone is not enough --
# without --ipc=host chromium dies mid-navigation on Docker's 64MB /dev/shm,
# and without the browser download Playwright has nothing to launch.
IPC = "--ipc=host"
runargs = old.get("runArgs")
pw_appended = False
ipc_added = False

if want_pw:
    kept[f"ghcr.io/{owner}/features/playwright-deps:1"] = {}

    # Merge, never replace: a project may already set runArgs for its own
    # reasons. --shm-size is the alternative fix for the same problem, so if it
    # is already there, adding --ipc=host would be redundant.
    if runargs is None:
        runargs = [IPC]
        ipc_added = True
    elif isinstance(runargs, list):
        if any("--shm-size" in str(a) for a in runargs):
            print("NOTE::runArgs already sets --shm-size; not adding --ipc=host "
                  "(they fix the same thing)", file=sys.stderr)
        elif IPC not in runargs:
            runargs = list(runargs) + [IPC]
            ipc_added = True
    else:
        print(f'WARN::runArgs is a {type(runargs).__name__}, not a list; add "{IPC}" '
              "by hand or chromium will crash on the 64MB /dev/shm", file=sys.stderr)

    # The browser download needs the playwright CLI, which comes from the
    # PROJECT's dependencies -- the feature deliberately does not provide it.
    # So it is only appended when postCreateCommand already installs those
    # dependencies, and goes last so it runs after them. Appending it to a
    # postCreateCommand with no install step produces a command that cannot
    # work: it fails with "playwright: not found" (exit 127) and aborts
    # container creation. A migration must never generate that.
    INSTALLS_DEPS = (
        "pip install", "pip3 install", "-m pip install", "poetry install",
        "uv sync", "uv pip install", "pdm install", "pipenv install",
        "npm ci", "npm install", "yarn install", "pnpm install",
    )
    if leftover is None:
        print('WARN::postCreateCommand is not a plain string, so "playwright install '
              'chromium" was NOT appended; add it by hand', file=sys.stderr)
    elif any("playwright install" in s for s in leftover):
        pass                                  # already there; do not duplicate
    elif any(any(k in s for k in INSTALLS_DEPS) for s in leftover):
        leftover.append("playwright install chromium")
        pw_appended = True
    else:
        print('WARN::postCreateCommand has no dependency-install step to anchor it to, '
              'so "playwright install chromium" was NOT added -- on its own it would '
              'fail with "playwright: not found" and abort container creation. Add it '
              "after whatever installs this project's dependencies, e.g.\n"
              '      "postCreateCommand": "pip install -e \'.[test]\' '
              '&& playwright install chromium"', file=sys.stderr)

    # Report only what was actually done -- the runArgs and postCreateCommand
    # edits each have cases where they are deliberately skipped or impossible,
    # and a summary that overstates them is worse than none.
    did = ["the playwright-deps feature"]
    if ipc_added:
        did.append('"%s" in runArgs' % IPC)
    if pw_appended:
        did.append('"playwright install chromium" in postCreateCommand')
    print("NOTE::added " + ", ".join(did) + ". The project must supply playwright "
          "itself (e.g. pytest-playwright in its test dependencies)", file=sys.stderr)
else:
    evidence = frontend_evidence(project)
    if evidence:
        print("NOTE::looks like a frontend project (%s); re-run with --playwright "
              "to add playwright-deps" % ", ".join(evidence[:3]), file=sys.stderr)

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

# Preserve any non-Claude postCreateCommand work.
if leftover is None:
    new["postCreateCommand"] = pcc
elif leftover:
    new["postCreateCommand"] = " && ".join(leftover)
    # Count only what came from the original file; the appended browser download
    # is reported by the --playwright NOTE above, not as something preserved.
    carried = len(leftover) - (1 if pw_appended else 0)
    if carried:
        print(f"NOTE::preserved {carried} non-Claude postCreateCommand step(s); review them",
              file=sys.stderr)

# runArgs is handled explicitly above rather than left to the unrecognised-keys
# path below, which would clobber a merged value with the original.
if runargs is not None:
    new["runArgs"] = runargs

# Carry over anything we do not recognise, so nothing is silently lost.
HANDLED = {"name", "image", "features", "remoteUser", "mounts", "containerEnv",
           "postCreateCommand", "initializeCommand", "runArgs"}
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
