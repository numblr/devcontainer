 # devcontainer

Reusable devcontainer Features for running Claude Code in a container.

Previously this repo held one folder per use case (`plain/`, `latex/`,
`autoupdate/`, `did-docker/`, `sandbox/`), each a near-identical copy of the same
`devcontainer.json` plus the same two scripts. That layout drifted: see
[Why this changed](#why-this-changed).

Now there is **one setup**. Per-project variation is a base image plus feature
references, not a forked folder.

## Features

| Feature | What it does |
|---|---|
| `claude-dev` | Installs Claude Code (native installer, user-owned so background auto-update works), seeds `~/.claude` from a host bind-mount, declares the per-container config volume, and enables the rtk Claude Code hook. |
| `latex` | TeX Live subset: `pdflatex`, `bibtex`, `biber`, plus pgfplots/TikZ, natbib, cleveref, mathtools/bm, booktabs and the recommended fonts. |
| `playwright-deps` | System libraries and fonts for Playwright's headless Chromium, so Claude can verify frontend code by writing and running Playwright tests. **Installs no browser and no Playwright** — see below. |

All are published to `ghcr.io/numblr/features/<id>` by
[`.github/workflows/release.yml`](.github/workflows/release.yml) on push to
`main`. Projects pin the **major** (`:1`) so fixes arrive on rebuild.

## Using it in a project

Copy [`examples/plain-devcontainer.json`](examples/plain-devcontainer.json) to
`.devcontainer/devcontainer.json` and set the image. See also
[`did-docker`](examples/did-docker-devcontainer.json) (pinned Python +
docker-in-docker), [`latex`](examples/latex-devcontainer.json) and
[`frontend`](examples/frontend-devcontainer.json).

```jsonc
{
  "name": "${localWorkspaceFolderBasename}",
  "image": "mcr.microsoft.com/devcontainers/python:3.12",
  "features": { "ghcr.io/numblr/features/claude-dev:1": {} },
  "remoteUser": "vscode",
  "initializeCommand": "mkdir -p ~/.claude-devcon-config ~/.claude-devcon-shared && touch ~/.claude-devcon-shared/.credentials.json",
  "mounts": [
    "source=${localEnv:HOME}/.claude-devcon-config,target=/home/vscode/.claude-seed,type=bind,readonly",
    "source=${localEnv:HOME}/.claude-devcon-shared/.credentials.json,target=/home/vscode/.claude/.credentials.json,type=bind"
  ]
}
```

### Host setup (once per machine)

```sh
mkdir -p ~/.claude-devcon-config          # seed: settings.json, .claude.json, skills/
mkdir -p ~/.claude-devcon-shared
touch    ~/.claude-devcon-shared/.credentials.json
chmod 600 ~/.claude-devcon-shared/.credentials.json
```

`initializeCommand` also does this, so a fresh machine works without the manual
step. Sign in once in any container; the credentials file is shared, so other
containers are already signed in.

### Adding Playwright to a project

Three edits to `.devcontainer/devcontainer.json`, then a rebuild. Complete file:
[`examples/frontend-devcontainer.json`](examples/frontend-devcontainer.json).

**1. The feature**, alongside `claude-dev`:

```jsonc
"features": {
  "ghcr.io/numblr/features/claude-dev:1": {},
  "ghcr.io/numblr/features/playwright-deps:1": {}
}
```

**2. `runArgs` — required, not optional.** Docker gives the container a 64 MB
`/dev/shm`; chromium outgrows it mid-navigation and fails as a confusing
`Target closed`:

```jsonc
"runArgs": ["--ipc=host"]
```

Use `["--shm-size=1g"]` instead if `--ipc=host` is unacceptable. If you cannot
change `runArgs` at all, pass `args=["--disable-dev-shm-usage"]` to every
`chromium.launch()` instead.

**3. The browser download**, which belongs to the project — the feature installs
system libraries only, and Playwright pins the browser revision to the installed
`playwright` version, so a pre-baked browser would be the wrong one:

```jsonc
"postCreateCommand": "pip install -e '.[test]' && playwright install chromium"
```

Needs `pytest-playwright` among the project's test dependencies (or
`pip install pytest-playwright` directly). ~170 MB into `~/.cache/ms-playwright`,
re-downloaded on each rebuild.

Then **Dev Containers: Rebuild Container** — not restart. `postCreateCommand`
only runs on container create.

#### Verify

Self-contained, so it does not need the app running:

```sh
python -c "
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(); pg.set_content('<h1>ok</h1>')
    print(pg.inner_text('h1')); b.close()"
```

`playwright install chromium` printing `is already installed` and that command
printing `ok` means the setup is complete.

#### How Claude uses it

By writing a test and running it, not by driving a browser interactively. Start
the dev server, then let Claude iterate on a spec:

```python
# tests/test_settings.py
def test_settings_renders(page):
    errors = []
    page.on("console", lambda m: m.type == "error" and errors.append(m.text))
    page.goto("http://localhost:5173/settings")
    assert page.inner_text("h1") == "Settings"
    assert errors == []          # catches the blank-page-with-a-TypeError case
    page.screenshot(path="/tmp/settings.png")   # Claude can read the PNG
```

`localhost` works directly — the dev server runs in the same container. Port
forwarding only matters for viewing it in your own browser.

### Why some things cannot move into the feature

A Feature may declare `mounts`, `containerEnv`, `customizations` and lifecycle
hooks, and `${devcontainerId}` **is** substituted in a Feature's `mounts` — which
is why the per-container config volume lives in `claude-dev`. But:

- **`${localEnv:*}` is not specified for Feature metadata**, so the two *host*
  bind-mounts (seed, credentials) must stay in each project's file.
- **`initializeCommand` is not a Feature hook**, so it stays too.
- **`runArgs` is not Feature metadata**, so `playwright-deps` cannot supply the
  `--ipc=host` that chromium needs. It stays in the project file, visible, in
  the same way `docker-in-docker`'s `privileged` does.
- **The Playwright browser download cannot move in either**, for two independent
  reasons: Feature lifecycle hooks run *before* the project's
  `postCreateCommand`, so the project venv does not exist yet and `playwright`
  is not importable; and Playwright pins an exact browser revision to the
  installed `playwright` version, so a pre-baked browser would be the wrong
  revision and be re-downloaded anyway.

Note the asymmetry in how mounts are written. A project's `devcontainer.json`
accepts the shorthand **string** form, but a Feature's `devcontainer-feature.json`
requires the **object** form -- the string form fails metadata validation with
`/mounts/0 ... must be object`:

```jsonc
// devcontainer.json          -> string form is fine
"mounts": ["source=...,target=...,type=volume"]

// devcontainer-feature.json  -> object form REQUIRED (target and type mandatory)
"mounts": [{ "source": "...", "target": "...", "type": "volume" }]
```

## Design notes

- **`remoteUser: vscode` is assumed.** `claude-dev` sets
  `CLAUDE_CONFIG_DIR=/home/vscode/.claude` via `containerEnv`, and Feature
  metadata has no option substitution, so the path is a literal. True for every
  `mcr.microsoft.com/devcontainers/*` image.
- **`node` is optional.** Claude Code no longer needs it — the native installer
  ships a self-contained binary. Add `ghcr.io/devcontainers/features/node:1`
  only where `npx`/MCP servers or JS tooling need it.
- **`docker-in-docker` is deliberately not wrapped.** Reference upstream
  `ghcr.io/devcontainers/features/docker-in-docker:2` per project: it carries
  `privileged: true`, a host-level decision that should stay visible where the
  project is configured, and dind-vs-docker-outside-of-docker is a per-project
  call about that project's mount topology.
- **Credentials are a host bind-mount, not a token.** `CLAUDE_CODE_OAUTH_TOKEN`
  is positioned for CI/Codespaces and misbehaves with the interactive CLI.
  Accepted trade-off: the file is readable inside the container, and concurrent
  containers share it and refresh it in place.
- **Seeding is once-only**, guarded by `.initialized-from-seed` inside the
  volume. Host seed changes reach an existing container only when its volume is
  removed. Deliberate: `settings.json` is both seed config *and* where Claude
  writes in-session permission approvals, so a re-sync rule would have to
  arbitrate between them.
- **Order is load-bearing**: seed, *then* rtk. The seed ships `settings.json`;
  rtk patches it. Reversed, the copy silently removes the hook.
  `test/claude-dev/test.sh` asserts the order in `postcreate.sh`.
- **`playwright-deps` resolves package names at build time, not from a hardcoded
  list.** The 64-bit `time_t` transition renamed six of them in Debian 13 and
  Ubuntu 24.04 (`libasound2` → `libasound2t64`, and likewise `libatk1.0-0`,
  `libatk-bridge2.0-0`, `libatspi2.0-0`, `libcups2`, `libglib2.0-0`), while
  Debian 11–12 and Ubuntu 22.04 keep the old names. Playwright's own
  `install-deps` has no Debian 13 entry at all, which is the reason this feature
  exists rather than just calling it. The `bookworm` scenario in
  `test/playwright-deps/scenarios.json` keeps the fallback path exercised, and
  fails loudly if its image ever stops being pre-`t64`.
- **`playwright-deps` treats `apt-get update` as best-effort.** apt fails the
  whole update if any single source fails, and old images carry stale
  third-party keys — the pinned `python:1-3.10-bookworm` used by the `bookworm`
  scenario has a yarn repo whose key is gone, so a strict update exits 100 on an
  otherwise fine image. A failed update is reported and execution continues, but
  the script then aborts if no package index was fetched at all, so a genuinely
  broken apt setup still fails loudly instead of being misreported as a missing
  package. `src/latex/install.sh` still updates strictly; it has not needed this.
- **Floating `mcr.microsoft.com/devcontainers/python:<minor>` tags move across
  Debian releases.** `python:3.10` is currently labelled
  `dev.containers.variant=3.10-trixie` — so even `did-docker`, which pins only
  the Python minor, is on trixie today and will move again. That is why the
  `bookworm` scenario pins an explicit `1-3.10-bookworm`, and why the apt names
  are resolved at build time rather than written down.
- **Claude verifies frontends by writing tests, not by driving a browser.** An
  MCP browser server was the alternative; it would put ~20 tool definitions into
  *every* session in the container, including the backend-only ones. The chosen
  loop is slower per iteration and only checks what the test asserts, but it
  leaves a committable artifact behind and costs idle projects nothing.

## Migrating an existing project

Projects are not reachable from inside this repo's container, so run this **on
the host**. Dry run by default:

```sh
tools/migrate-devcontainer.sh --owner numblr ~/path/to/project          # preview
tools/migrate-devcontainer.sh --owner numblr --write ~/path/to/project  # apply
```

It preserves the base image and non-Claude features, drops what `claude-dev` now
owns, writes a `.bak-<timestamp>` backup, and removes
`.devcontainer/scripts/` **only** when it contains nothing but the known old
scripts. Comments are not carried over — it warns when the original had any.

Add `--playwright` for a project whose frontend you want verifiable, which
applies all three edits from
[Adding Playwright to a project](#adding-playwright-to-a-project) at once:

```sh
tools/migrate-devcontainer.sh --owner numblr --playwright --write ~/path/to/web
```

It merges `--ipc=host` into any existing `runArgs` rather than replacing them,
skips it when `--shm-size` is already set, and appends the browser download
*after* the project's own install steps, since the `playwright` CLI comes from
the project's dependencies. The summary names only the edits it actually made —
`runArgs` that is not a list, and a non-string `postCreateCommand`, are reported
for you to fix by hand instead of being rewritten. Re-running is safe: neither
the flag nor the browser download is duplicated.

The flag is opt-in because no old config implies a browser, so adding it by
default would grant every migrated project a capability it never had, at +37 apt
packages per image. Run without it and the script still prints a `NOTE` when the
project looks like a frontend (a `package.json` naming vite/react/vue/svelte or
`@playwright/test`, a `playwright.config.*`, `pytest-playwright` in
`pyproject.toml`, or an `e2e/` directory), so the reminder arrives where you
would otherwise forget it.

Then rebuild and verify:

```sh
rtk init --show   # expect Hook present, not "not found"
claude doctor     # no conflicting installations; auto-updates enabled
```

## Development

```sh
npm install -g @devcontainers/cli
devcontainer features test --base-image mcr.microsoft.com/devcontainers/python:3.12 .
```

Bump `version` in `src/<id>/devcontainer-feature.json` to release; the workflow
only pushes versions that do not already exist.

## Why this changed

The copied folders had drifted into real, silent breakage:

1. **The rtk hook never installed in 3 of 5 configs.** `rtk init --global`
   *prompts* before patching `settings.json`, and `postCreateCommand` has no
   TTY, so the prompt was never answered — and `|| echo WARNING` hid it.
   `--auto-patch` means "same as `-g`, no prompt". `plain/` and `latex/` had it;
   `.devcontainer/`, `autoupdate/` and `did-docker/` did not, so their `RTK.md`
   told Claude output was being condensed while nothing condensed it.
2. **The `autoupdate` chown did not achieve auto-update.** The upstream
   `claude-code` Feature runs `npm install -g` as root, so global `node_modules`
   is root-owned. The chown covered only `$(npm root -g)/@anthropic-ai`, but
   `npm install -g` also rewrites `node_modules/.package-lock.json`, the `bin/`
   symlinks and the per-platform optional dependency. `|| true` hid the failure.
   The native installer removes the problem instead of patching it.
3. **`sandbox/ubuntu-devcontainer.json` was never valid JSON** — the
   `"features": {` wrapper line is missing.
4. **Three spellings of the host seed path** across the folders.
5. **Two versions of `init-claude-config.sh`**, and the newer one's warning named
   a path (`~/.claude-shared`) that no config ever mounted.
6. `.devcontainer/` and `autoupdate/` were byte-identical.

The old folders are kept for now as a rollback path.
