<div align="center">

# odysseus-nix

[Install](#install) • [Usage](#usage) • [Configuration](#configuration) • [Flake outputs](#flake-outputs) • [Contribute](#contribute)

[![Release](https://img.shields.io/github/v/tag/KangaZero/odysseus-nix?style=flat-square&label=release&color=58839b)](https://github.com/KangaZero/odysseus-nix/tags)
[![CI](https://img.shields.io/github/actions/workflow/status/KangaZero/odysseus-nix/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/KangaZero/odysseus-nix/actions/workflows/ci.yml)
![Latest commit](https://img.shields.io/github/last-commit/KangaZero/odysseus-nix?style=flat-square)
![Supports Python 3.14](https://img.shields.io/badge/Python-3.14-3776ab?style=flat-square&logo=python&logoColor=white)
![Nix flake](https://img.shields.io/badge/Nix-flake-5277c3?style=flat-square&logo=nixos&logoColor=white)
[![License: MIT](https://img.shields.io/github/license/KangaZero/odysseus-nix?style=flat-square)](./LICENSE)

</div>

---

> [!IMPORTANT]
> **Upstream Odysseus development has moved to the `dev` branch.** `dev` is now
> upstream's default branch, and everything from the `dev` branch onwards is what
> this flake tracks — rolling `main` clones upstream's default branch, and every
> release branch pins a commit from it. Upstream's `main` branch still exists but
> is **not** where development happens, so do not pin it. Upstream also
> transferred organisation from `pewdiepie-archdaemon` to
> [`odysseus-dev`](https://github.com/odysseus-dev/odysseus); the old URLs
> redirect, but `odysseus-dev` is the canonical location and the one this flake
> clones from.

### Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Install](#install)
- [Usage](#usage)
- [Configuration](#configuration)
- [Recipes](#recipes)
- [Optional services](#optional-services)
- [What's bundled](#whats-bundled)
- [Flake outputs](#flake-outputs)
- [CI and the pre-push hook](#ci-and-the-pre-push-hook)
- [Contribute](#contribute)
- [License](#license)

# Introduction

> It is a story as old as time. A developer clones a Python app, meets a wall of
> apt packages, dlopen failures, and a `libxcb.so.1: cannot open shared object
file` that no clean `pip install` explains. This flake is the escape hatch.

**odysseus-nix** is a Nix flake providing a reproducible dev environment for
[Odysseus][odysseus] — Python 3.14, Node.js LTS, and every system-level
dependency needed to build the project's native Python wheels. The system deps
mirror upstream's `Dockerfile` so that what builds in the container builds here.

Two branches of behaviour:

| Branch             | Upstream odysseus checkout                                               |
| ------------------ | ------------------------------------------------------------------------ |
| `main`             | **Rolling.** Clones upstream `dev` HEAD, no rev pin.                     |
| `vX.Y.Z` (release) | **Pinned.** Bakes in an `odysseusRev`; the cache clone auto-syncs to it. |

# Features

- **Hands-off.** `nix run` clones the app, builds a venv, installs deps, and
  serves it. No manual steps.
- **Dockerfile-mirrored system deps**, so native wheels (numpy, cryptography,
  bcrypt, PyMuPDF, onnxruntime) build on every supported arch.
- **Reproducible app checkouts** via release branches that pin an upstream rev.
- **Opt-out, not opt-in.** Automation is on by default; every behaviour has an
  env-var escape hatch.
- **One gate.** `just test` runs formatting, lint, flake checks, and builds —
  the same command CI and the `pre-push` hook run.
- **Opt-in browser shell** for Odysseus' built-in Browser MCP server, keeping a
  1.7 GiB chromium closure out of the default shell.

# Prerequisites

[Nix][nix] with flakes enabled. The [Determinate Nix installer][determinate]
turns flakes on by default; on upstream installs add
`experimental-features = nix-command flakes` to `~/.config/nix/nix.conf`.

Supported systems:

- `x86_64-linux`
- `aarch64-linux`
- `aarch64-darwin` (Apple Silicon)

> [!IMPORTANT]
> `x86_64-darwin` (Intel Mac) is **no longer supported**. nixpkgs 26.11 dropped
> the platform, so `legacyPackages.x86_64-darwin` throws during evaluation; the
> flake filters it out of its system list. Intel Macs need a nixpkgs pinned to
> the `nixpkgs-26.05-darwin` branch, which receives security fixes until the end
> of 2026.

# Install

**Run Odysseus with one command — no clones required:**

```sh
nix run github:KangaZero/odysseus-nix
```

What that does:

1. Clones [odysseus][odysseus] into `${XDG_CACHE_HOME:-~/.cache}/odysseus-nix/odysseus`
   (one-time, shallow).
2. Creates `.venv/` in that checkout and installs `requirements.txt`,
   `python-magic`, and `requirements-optional.txt` (the last unless
   `ODYSSEUS_INSTALL_OPTIONAL=0`).
3. Starts `uvicorn app:app --reload` on `:7000`.

Subsequent runs reuse the cache; installs are skipped unless the manifests
changed.

**Use an existing checkout** — pass a path, set `ODYSSEUS_DIR`, or just `cd`
into one:

```sh
nix run github:KangaZero/odysseus-nix -- /path/to/odysseus
ODYSSEUS_DIR=/path/to/odysseus nix run github:KangaZero/odysseus-nix
cd /path/to/odysseus && nix run github:KangaZero/odysseus-nix
```

**Use a fork** — override the clone URL:

```sh
ODYSSEUS_REPO_URL=https://github.com/you/odysseus-fork.git \
  nix run github:KangaZero/odysseus-nix
```

**For an interactive dev shell** (with `just`, auto-installed deps, the full
toolchain on `$PATH`):

```sh
git clone https://github.com/KangaZero/odysseus-nix.git
cd odysseus-nix
nix develop
```

The dev shell looks for a sibling `../odysseus` checkout; point it anywhere with
`ODYSSEUS_DIR=/path/to/odysseus nix develop`. Then run `just dev`.

# Usage

## Pinning for reproducibility

`nix run` and `nix develop` resolve `main` by default, which is **rolling** — the
launcher shallow-clones upstream's default branch (`dev`) with no rev pin, so it
tracks upstream HEAD and `ODYSSEUS_REV` has _no effect_. Pinning the flake ref
pins the _Nix env_, not the odysseus checkout:

```sh
nix run github:KangaZero/odysseus-nix/<commit-sha>
nix develop github:KangaZero/odysseus-nix/<commit-sha>
```

For a reproducible **upstream odysseus checkout**, target a **release branch**.
Release branches (`v0.1.0` … `v0.8.0`, `v1.0.0`, …) bake in a specific upstream rev, and the managed
cache clone auto-syncs to it on first run, so two machines get the same checkout:

```sh
nix run --refresh github:KangaZero/odysseus-nix/v1.0.0
nix develop github:KangaZero/odysseus-nix/v1.0.0
```

> [!NOTE]
> Rev-pinning — and the `ODYSSEUS_REV` / `ODYSSEUS_NO_SYNC` overrides — exist
> **only on release branches, not on `main`**. `--refresh` is only needed the
> first time after a new commit lands on the branch; it bypasses Nix's flake
> tarball-ttl cache.

Best practice is to consume this flake as an input from your own flake, so the
rev is captured in your `flake.lock`.

## As an input to your own flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    odysseus-nix = {
      url = "github:KangaZero/odysseus-nix";
      # Share your nixpkgs to avoid fetching a second copy and to keep
      # versions consistent. The flake uses `pkgs.nodejs` (default LTS),
      # so it follows whatever nixpkgs you pin.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, odysseus-nix, ... }: {
    # Re-export the dev shell as-is:
    devShells.x86_64-linux.default =
      odysseus-nix.devShells.x86_64-linux.default;

    # Or compose it into your own shell:
    devShells.x86_64-linux.mine =
      let pkgs = import nixpkgs { system = "x86_64-linux"; };
      in pkgs.mkShell {
        inputsFrom = [ odysseus-nix.devShells.x86_64-linux.default ];
        packages = [ pkgs.ripgrep pkgs.fd ];
      };
  };
}
```

## With home-manager

**Recommended:** install the `odysseus-dev` launcher so `odysseus-dev` is on your
`$PATH` everywhere. It is a single script with no toolchain in your user profile,
so nothing collides with packages you already have.

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    odysseus-nix = {
      url = "github:KangaZero/odysseus-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, odysseus-nix, ... }: {
    homeConfigurations."you" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "aarch64-darwin"; };
      extraSpecialArgs = { inherit odysseus-nix; };
      modules = [{ pkgs, odysseus-nix, ... }: {
        home.packages = [
          odysseus-nix.packages.${pkgs.stdenv.hostPlatform.system}.odysseus-dev
        ];
      }];
    };
  };
}
```

After `home-manager switch`, `odysseus-dev [path-to-checkout]` works from any
shell.

> [!WARNING]
> The **alternative** — swapping `odysseus-dev` for `odysseus-env` to surface
> every tool at the user level — installs a `buildEnv` aggregating ~20 packages.
> It collides with anything in your `home.packages` that ships the same binary
> (commonly `just`, `nodejs`, `curl`, `git`, `cmake`). Remove those first, or
> stick with `odysseus-dev` and use `nix develop github:KangaZero/odysseus-nix`
> for the full toolchain on demand.

## With direnv

An `.envrc` ships in this repo. Install [direnv][direnv], then:

```sh
cd odysseus-nix
direnv allow
```

The shell now auto-loads whenever you `cd` in. The `.envrc` includes
`watch_file flake.lock`, so direnv re-enters the shell after `nix flake update`
— no manual `direnv reload`.

# Configuration

Entering `nix develop` from this repo:

1. `cd`s into `$ODYSSEUS_DIR` (default `../odysseus`).
2. Creates `data/`, `logs/`, `services/cache/search/` — the app expects them on
   first boot.
3. Creates/activates `.venv/` inside the checkout.
4. Installs `requirements.txt`, `python-magic`, `requirements-optional.txt`, and
   npm deps — but only when those manifests change (mtime-marker check, so
   re-entering is a no-op).
5. Exports `JUST_JUSTFILE` so `just <recipe>` works from anywhere in the shell.

Env knobs (apply to both `nix run` and `nix develop` unless noted):

| Variable                      | Default                                                                | Effect                                                                     |
| ----------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `ODYSSEUS_DIR`                | `nix run`: auto-detected or cache clone · `nix develop`: `../odysseus` | Path to the odysseus checkout.                                             |
| `ODYSSEUS_REPO_URL`           | `https://github.com/odysseus-dev/odysseus.git`                         | Clone URL used by `nix run` when no checkout is found (point at a fork).   |
| `ODYSSEUS_REV`                | the branch's baked-in `odysseusRev`                                    | **Release branches only.** Full SHA to sync the managed cache clone to.    |
| `ODYSSEUS_NO_SYNC`            | `0`                                                                    | **Release branches only.** Set to `1` to skip syncing the cache clone.     |
| `ODYSSEUS_AUTO_INSTALL`       | `1`                                                                    | **Dev shell only.** Set to `0` to skip auto-`pip install` / `npm install`. |
| `ODYSSEUS_INSTALL_OPTIONAL`   | `1`                                                                    | Set to `0` to skip installing `requirements-optional.txt`.                 |
| `ODYSSEUS_BROWSER_EXECUTABLE` | unset (set by `nix develop .#browser`)                                 | Browser binary handed to the built-in Browser MCP server.                  |
| `APP_PORT`                    | `7000`                                                                 | Port for `just run` / `nix run`.                                           |
| `VENV_DIR`                    | `.venv` inside the resolved checkout                                   | Path to the Python venv.                                                   |
| `XDG_CACHE_HOME`              | `~/.cache`                                                             | Parent of the auto-clone cache (`$XDG_CACHE_HOME/odysseus-nix/odysseus`).  |

# Recipes

After `nix develop`, run `just` (from anywhere — `JUST_JUSTFILE` is exported).

**CI gate** — what `just test`, CI, and the `pre-push` hook enforce:

```text
just test            # fmt-check + lint + check + build — the one CI runs
just test-all        # test + install + install-optional + install-node + pytest
just fmt-check       # treefmt --ci (nix/shell/md/yaml — verify formatting)
just lint            # statix + deadnix + shellcheck
just check           # native flake check + all-systems eval (no cross-build)
just build           # nix build .#default .#odysseus-dev
just fmt             # treefmt in-place (nix/shell/md/yaml — auto-fix)
just install-hooks   # wire up the .githooks/pre-push hook
just lock-update     # nix flake update
```

**Odysseus app recipes** — operate on `$ODYSSEUS_DIR`:

```text
just install          # pip install -r requirements.txt
just install-optional # pip install -r requirements-optional.txt
just install-node     # npm install
just install-all      # install + install-node
just run              # uvicorn app:app --reload --host 0.0.0.0 --port $APP_PORT
just dev              # alias for `run`
just pytest [args...] # pytest, with optional args (e.g. `just pytest -k auth`)
just docker-up        # docker compose up --build -d
just docker-down      # docker compose down
just docker-logs      # docker compose logs -f
just clean            # rm -rf .venv node_modules (forces a clean re-install)
just info             # print resolved paths + versions
```

# Optional services

These need a one-time setup step beyond `nix develop`.

## ChromaDB (vector RAG + semantic memory)

`requirements.txt` ships `chromadb-client`, which talks to a **server** — it has
no local persistence. Start one on `localhost:8100`:

```sh
pip uninstall -y chromadb-client && pip install chromadb
just chromadb
```

Data lands in `$ODYSSEUS_DIR/data/chromadb`.

## Browser MCP (`@playwright/mcp`)

The built-in Browser MCP server lets Odysseus drive a real browser via
`npx @playwright/mcp`. It needs an actual chromium binary: the app resolves one
from `ODYSSEUS_BROWSER_EXECUTABLE` (or a `chromium` on `$PATH`) and hands it to
Playwright as `--executable-path` — and it **overrides**
`PLAYWRIGHT_BROWSERS_PATH` with its own local cache, so the dev shell's
playwright-driver browsers cannot satisfy it.

Because chromium is a ~1.7 GiB, Linux-only closure, it is kept out of the
default shell. Use the opt-in browser shell, which provisions chromium and
exports `ODYSSEUS_BROWSER_EXECUTABLE`:

```sh
nix develop .#browser
```

Optionally seed the npx cache first so the MCP server starts without a download
on first use:

```sh
just playwright-mcp
```

Then start the app (`just run`). To use your own browser instead, export
`ODYSSEUS_BROWSER_EXECUTABLE=/path/to/chromium` before launching.

# What's bundled

System-level deps mirror the project `Dockerfile` so native Python wheels build
cleanly on every supported arch:

- Python 3.14 + pip + virtualenv
- Node.js (default LTS from the consuming nixpkgs — 24.x on the pinned lock)
- just (task runner)
- git, cmake, curl, tmux, openssh, pkg-config
- nixpkgs-fmt, statix, deadnix, shellcheck (used by `just test`)
- zlib, openssl, libffi, libxml2/xslt (wheel build headers), file/libmagic
  (the shared library `python-magic` dlopens; the wrapper itself is pip-installed
  automatically — see the note below)
- gosu (Linux only — used by the Docker entrypoint)
- libGL, glib, libxcb (Linux only — opencv/cv2 runtime libs for the
  Real-ESRGAN path)

Python packages are installed via `pip` into the venv, not Nix — that keeps the
flake small and avoids fighting nixpkgs over PyPI versions like
`chromadb-client` and `fastembed`.

> [!NOTE]
> The **dev shell** additionally exports `PLAYWRIGHT_BROWSERS_PATH` at
> `playwright-driver.browsers` so Playwright needs no runtime browser download.
> That store path is a dev-shell environment variable, **not** part of the
> `odysseus-env` package closure — `home.packages` users do not get it.

**Optional Python deps** — installed from `requirements-optional.txt` unless
`ODYSSEUS_INSTALL_OPTIONAL=0`:

- `faster-whisper` — local transcription (GPU-accelerated when available)
- `ddgs` — DuckDuckGo as a search provider
- `PyMuPDF` — richer PDF extraction
- `markitdown[docx,pptx,xlsx,xls]` — Office document conversion
- `kokoro` + `soundfile` — local text-to-speech. Marker-gated to
  `python_version >= "3.11" and < "3.13"`, so **pip skips both on this flake's
  Python 3.14**.

> [!NOTE]
> `python-magic` appears in **no** requirements file — upstream installs it in
> the `Dockerfile` only, because it resolves `libmagic` at import time. This
> flake therefore installs `python-magic==0.4.27` itself (matching the
> Dockerfile pin, which is also the newest release on PyPI) in both the launcher
> and the dev shell, so content-based MIME sniffing in `src/upload_handler.py`
> works here exactly as it does in the container. The install is marker-guarded
> at `$VENV_DIR/.python-magic-<version>.installed` and is non-fatal — if it
> fails, sniffing degrades to extension detection and startup continues.

# Flake outputs

| Output                            | What                                                                                         |
| --------------------------------- | -------------------------------------------------------------------------------------------- |
| `devShells.${system}.default`     | Interactive dev shell (consumed by `nix develop`).                                           |
| `devShells.${system}.browser`     | Default shell + chromium for the built-in Browser MCP (`nix develop .#browser`). Linux only. |
| `packages.${system}.default`      | Alias for `odysseus-env`.                                                                    |
| `packages.${system}.odysseus-env` | buildEnv of every bundled tool — for home-manager users who want everything surfaced.        |
| `packages.${system}.odysseus-dev` | Launcher script that bootstraps a venv and runs uvicorn. Recommended for home-manager.       |
| `apps.${system}.default`          | Same launcher, exposed for `nix run`.                                                        |
| `checks.${system}.formatting`     | treefmt check — fails if the tree is unformatted. Enforced in CI.                            |
| `formatter.${system}`             | `treefmt` (nixpkgs-fmt + shfmt + prettier), exposed as `nix fmt`.                            |

# CI and the pre-push hook

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs `just test` on every
push and PR to `main`, across a matrix of native runners — `ubuntu-latest`
(x86_64-linux), `ubuntu-24.04-arm` (aarch64-linux), and `macos-latest`
(aarch64-darwin) — via the [Determinate Systems nix-installer][nix-installer].
No external cache service is required; runs are 2–5 min cold.

Release-branch pushes do **not** trigger CI automatically. Dispatch it manually:

```sh
gh workflow run ci.yml --ref v1.0.0
```

To require the checks before merging, enable branch protection on `main` (repo
settings → Branches → Add rule) with "Require status checks to pass before
merging" and add `test (ubuntu-latest)`, `test (ubuntu-24.04-arm)`, and
`test (macos-latest)`.

Install the local hook so the same gate runs before every push:

```sh
just install-hooks   # git config core.hooksPath .githooks
```

# Contribute

`just test` must print `✅ all checks passed` before anything is pushed — that is
the whole contract. Formatting is `nix fmt` (treefmt: nixpkgs-fmt, shfmt,
prettier); lint is statix + deadnix + shellcheck.

When upstream's `Dockerfile` apt list changes, re-check that `commonDeps` /
`linuxDeps` in [`flake.nix`](flake.nix) still cover it. Release conventions and
the full changelog live in [CHANGELOG.md](CHANGELOG.md).

# License

[MIT](./LICENSE).

[odysseus]: https://github.com/odysseus-dev/odysseus
[nix]: https://nixos.org/download
[determinate]: https://determinate.systems/nix
[direnv]: https://direnv.net/
[nix-installer]: https://github.com/DeterminateSystems/nix-installer-action
