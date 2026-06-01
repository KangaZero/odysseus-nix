# odysseus-nix

A Nix flake providing a reproducible dev environment for [Odysseus](https://github.com/pewdiepie-archdaemon/odysseus) — Python 3.12, Node.js (LTS), and every system-level dep needed to build the native Python wheels.

Works on:

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin` (Intel Mac)
- `aarch64-darwin` (Apple Silicon)

## Quickstart

You need [Nix](https://nixos.org/download) with flakes enabled. (The [Determinate Nix installer](https://determinate.systems/nix) turns flakes on by default. Upstream installs: add `experimental-features = nix-command flakes` to `~/.config/nix/nix.conf`.)

**Run Odysseus with one command — no clones required:**

```sh
nix run github:KangaZero/odysseus-nix
```

What this does:

1. Clones [odysseus](https://github.com/pewdiepie-archdaemon/odysseus) into `${XDG_CACHE_HOME:-~/.cache}/odysseus-nix/odysseus` (one-time, shallow).
2. Creates `.venv/` in that checkout and `pip install`s `requirements.txt`.
3. Starts `uvicorn app:app --reload` on `:7000`.

Subsequent runs reuse the cache; `pip install` is skipped unless `requirements.txt` changed.

**Use an existing checkout** — pass a path, set `ODYSSEUS_DIR`, or just `cd` into one:

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

**For an interactive dev shell** (with `just`, auto-installed deps, etc.):

```sh
git clone https://github.com/KangaZero/odysseus-nix.git
cd odysseus-nix
nix develop
```

The dev shell looks for a sibling `../odysseus` checkout. Point at any path with `ODYSSEUS_DIR=/path/to/odysseus nix develop`.

Then either `uvicorn app:app --reload` or `just dev`.

## Three ways to use it

### 1. Standalone — `nix run` or `nix develop`

The Quickstart above. `nix run` is the one-shot "just start the server" path; `nix develop` is the interactive shell with the full toolchain on `$PATH`.

Both forms always resolve `main` by default. To pin to a specific commit (recommended for reproducibility in scripts / CI):

```sh
nix run github:KangaZero/odysseus-nix/<commit-sha>
nix develop github:KangaZero/odysseus-nix/<commit-sha>
```

Best practice is to consume this flake as an input from your own flake (next section) so the rev is captured in your `flake.lock`.

### 2. Add as an input to your own flake

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

### 3. Add to home-manager

**Recommended:** add the `odysseus-dev` launcher so `odysseus-dev` is on your `$PATH` everywhere. It's a single script with no toolchain in your user profile, so there are no collisions with packages you already have (`just`, `nodejs`, `curl`, etc.).

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

After `home-manager switch`, `odysseus-dev [path-to-checkout]` works from any shell.

**Alternative:** if you actually want every tool (Python 3.12, Node, just, cmake, statix, …) surfaced at the user level — not just the launcher — swap `odysseus-dev` for `odysseus-env` above. ⚠️ Heads-up: `odysseus-env` is a `buildEnv` aggregating ~20 packages, so it'll collide with anything you have in `home.packages` that ships the same binary (commonly `just`, `nodejs`, `curl`, `git`, `cmake`). Remove those from your `home.packages` first, or stick with `odysseus-dev` and use `nix develop github:KangaZero/odysseus-nix` for the full toolchain on demand.

## What the dev shell does

When you enter `nix develop` from this repo:

1. `cd`s into `$ODYSSEUS_DIR` (default `../odysseus`).
2. Creates `data/`, `logs/`, `services/cache/search/` — the app expects them on first boot.
3. Creates/activates `.venv/` inside the checkout.
4. Runs `pip install -r requirements.txt` and `npm install` — but only when those manifests change (mtime-marker check, so re-entering is a no-op).
5. Exports `JUST_JUSTFILE` so `just <recipe>` works from anywhere in the shell.

Env knobs (apply to both `nix run` and `nix develop` unless noted):

| Variable | Default | Effect |
|---|---|---|
| `ODYSSEUS_DIR` | `nix run`: auto-detected or cache clone · `nix develop`: `../odysseus` | Path to the odysseus checkout. |
| `ODYSSEUS_REPO_URL` | `https://github.com/pewdiepie-archdaemon/odysseus.git` | Clone URL used by `nix run` when no checkout is found (point at a fork). |
| `ODYSSEUS_AUTO_INSTALL` | `1` | Dev shell only. Set to `0` to skip auto-`pip install`/`npm install`. |
| `ODYSSEUS_INSTALL_OPTIONAL` | `0` | Dev shell only. Set to `1` to also install `requirements-optional.txt` (DuckDuckGo search, PyMuPDF form-filling). |
| `APP_PORT` | `7000` | Port for `just run` / `nix run`. |
| `VENV_DIR` | `$ODYSSEUS_DIR/.venv` | Path to the Python venv. |
| `XDG_CACHE_HOME` | `~/.cache` | Parent of the auto-clone cache (`$XDG_CACHE_HOME/odysseus-nix/odysseus`). |

## Just recipes

After `nix develop`, run `just` (from anywhere — `JUST_JUSTFILE` is exported):

**CI gate** — these are what `just test` (and CI / git pre-push) enforce:

```text
just test            # fmt-check + lint + check + build — the one CI runs
just fmt-check       # nixpkgs-fmt --check (verify formatting)
just lint            # statix + deadnix + shellcheck
just check           # nix flake check --all-systems
just build           # nix build .#default .#odysseus-dev
just fmt             # nixpkgs-fmt (auto-fix)
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
just info             # print resolved paths + versions
```

## CI & git pre-push hook

`.github/workflows/ci.yml` runs `just test` on every push and PR on both `ubuntu-latest` and `macos-latest` via the [Determinate Systems nix-installer](https://github.com/DeterminateSystems/nix-installer-action) + [magic-nix-cache](https://github.com/DeterminateSystems/magic-nix-cache-action).

To require those checks before merging, enable branch protection on `main` in repo settings → Branches → Add rule:

- "Require status checks to pass before merging"
- Add `test (ubuntu-latest)` and `test (macos-latest)` as required checks.

To also block local pushes that don't pass, install the pre-push hook once per clone:

```sh
just install-hooks    # → git config core.hooksPath .githooks
```

The hook runs `just test` before every push; bypass for a single push with `git push --no-verify`.

## direnv

A `.envrc` ships in this folder. Install [direnv](https://direnv.net/), then:

```sh
cd odysseus-nix
direnv allow
```

The shell now auto-loads whenever you `cd` in.

## What's bundled

System-level deps mirror the project Dockerfile so native Python wheels build cleanly on every supported arch:

- Python 3.12 + pip + virtualenv
- Node.js (default LTS from the consuming nixpkgs — currently 22/24 on `nixos-unstable`)
- just (task runner)
- git, cmake, curl, tmux, openssh, pkg-config
- nixpkgs-fmt, statix, deadnix, shellcheck (used by `just test`)
- zlib, openssl, libffi, libxml2/xslt (wheel build headers)
- gosu (Linux only — used by the Docker entrypoint)

Python packages themselves are installed via `pip` into the venv, not Nix — keeps the flake small and avoids fighting nixpkgs over PyPI versions like `chromadb-client` and `fastembed`.

## Flake outputs

| Output | What |
|---|---|
| `devShells.${system}.default` | Interactive dev shell (consumed by `nix develop`). |
| `packages.${system}.default` | Alias for `odysseus-env`. |
| `packages.${system}.odysseus-env` | buildEnv of every bundled tool — for home-manager users who want everything surfaced. |
| `packages.${system}.odysseus-dev` | Launcher script that bootstraps a venv and runs uvicorn. Recommended for home-manager. |
| `apps.${system}.default` | Same launcher, exposed for `nix run`. |
| `formatter.${system}` | `nixpkgs-fmt`. |

## License

[MIT](./LICENSE).
