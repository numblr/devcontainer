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

Both are published to `ghcr.io/numblr/features/<id>` by
[`.github/workflows/release.yml`](.github/workflows/release.yml) on push to
`main`. Projects pin the **major** (`:1`) so fixes arrive on rebuild.

## Using it in a project

Copy [`examples/plain-devcontainer.json`](examples/plain-devcontainer.json) to
`.devcontainer/devcontainer.json` and set the image. See also
[`did-docker`](examples/did-docker-devcontainer.json) (pinned Python +
docker-in-docker) and [`latex`](examples/latex-devcontainer.json).

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

### Why some things cannot move into the feature

A Feature may declare `mounts`, `containerEnv`, `customizations` and lifecycle
hooks, and `${devcontainerId}` **is** substituted in a Feature's `mounts` — which
is why the per-container config volume lives in `claude-dev`. But:

- **`${localEnv:*}` is not specified for Feature metadata**, so the two *host*
  bind-mounts (seed, credentials) must stay in each project's file.
- **`initializeCommand` is not a Feature hook**, so it stays too.

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
