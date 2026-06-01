# odysseus-nix

A Nix flake that provides a reproducible dev environment for [Odysseus](https://github.com/pewdiepie-archdaemon/odysseus) — Python 3.12, Node 26, and every system-level dep needed to build the native Python wheels.

Works on:

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin` (Intel Mac)
- `aarch64-darwin` (Apple Silicon)

## Quickstart

You need [Nix](https://nixos.org/download) with flakes enabled. (The [Determinate Nix installer](https://determinate.systems/nix) turns flakes on by default. Upstream installs: add `experimental-features = nix-command flakes` to `~/.config/nix/nix.conf`.)

**Run Odysseus directly — no clone of this repo needed:**

```sh
git clone https://github.com/pewdiepie-archdaemon/odysseus.git
cd odysseus
nix run github:KangaZero/odysseus-nix
# → bootstraps a venv, pip-installs requirements, and starts uvicorn on :7000
```

Or pass the checkout path explicitly:

```sh
nix run github:KangaZero/odysseus-nix -- /path/to/odysseus
```

**For an interactive dev shell** (with `just`, auto-installed deps, etc.):

```sh
git clone https://github.com/KangaZero/odysseus-nix.git
git clone https://github.com/pewdiepie-archdaemon/odysseus.git
cd odysseus-nix
nix develop
# auto-cds into ../odysseus, sets up venv, installs deps
```

Then either `uvicorn app:app --reload` or `just dev`.

## Three ways to use it

### 1. Standalone — `nix run` or `nix develop`

The Quickstart above. `nix run` is the one-shot "just start the server" path; `nix develop` is the interactive shell with the full toolchain on `$PATH`.

You can pin a version:

```sh
nix run github:KangaZero/odysseus-nix/main
nix develop github:KangaZero/odysseus-nix/v0.1.0   # if you tag
```

### 2. Add as an input to your own flake

Pull in the dev shell or packages from your own `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    odysseus-nix.url = "github:KangaZero/odysseus-nix";
    # Optional: share your nixpkgs to avoid downloading two copies.
    odysseus-nix.inputs.nixpkgs.follows = "nixpkgs";
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

Pull `odysseus-env` (a buildEnv of every tool the dev shell ships) into your user profile:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    odysseus-nix.url = "github:KangaZero/odysseus-nix";
    odysseus-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, odysseus-nix, ... }: {
    homeConfigurations."you" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "aarch64-darwin"; };
      modules = [{
        home.packages = [
          odysseus-nix.packages.aarch64-darwin.odysseus-env
          # or just the launcher:
          # odysseus-nix.packages.aarch64-darwin.odysseus-dev
        ];
      }];
    };
  };
}
```

After `home-manager switch`, `python3.12`, `node`, `just`, `cmake`, etc. are on `$PATH` for your user — no `nix develop` required.

You can also install ad-hoc via `nix profile`:

```sh
nix profile install github:KangaZero/odysseus-nix#odysseus-env
nix profile install github:KangaZero/odysseus-nix#odysseus-dev
```

## What the dev shell does

When you enter `nix develop` from this repo:

1. `cd`s into `$ODYSSEUS_DIR` (default `../odysseus`).
2. Creates `data/`, `logs/`, `services/cache/search/` — the app expects them on first boot.
3. Creates/activates `.venv/` inside the checkout.
4. Runs `pip install -r requirements.txt` and `npm install` — but only when those manifests change (mtime-marker check, so re-entering is a no-op).
5. Exports `JUST_JUSTFILE` so `just <recipe>` works from anywhere in the shell.

Env knobs:

| Variable | Default | Effect |
|---|---|---|
| `ODYSSEUS_DIR` | `../odysseus` | Path to the odysseus checkout. |
| `ODYSSEUS_AUTO_INSTALL` | `1` | Set to `0` to skip auto-`pip install`/`npm install`. |
| `ODYSSEUS_INSTALL_OPTIONAL` | `0` | Set to `1` to also install `requirements-optional.txt` (DuckDuckGo search, PyMuPDF form-filling). |
| `APP_PORT` | `7000` | Port for `just run` / `nix run`. |
| `VENV_DIR` | `$ODYSSEUS_DIR/.venv` | Path to the Python venv. |

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
- Node.js 26 (for the optional Browser MCP server)
- just (task runner)
- git, cmake, curl, tmux, openssh, pkg-config
- zlib, openssl, libffi, libxml2/xslt (wheel build headers)
- gosu (Linux only — used by the Docker entrypoint)

Python packages themselves are installed via `pip` into the venv, not Nix — keeps the flake small and avoids fighting nixpkgs over PyPI versions like `chromadb-client` and `fastembed`.

## Flake outputs

| Output | What |
|---|---|
| `devShells.${system}.default` | Interactive dev shell (consumed by `nix develop`). |
| `packages.${system}.default` | Alias for `odysseus-env`. |
| `packages.${system}.odysseus-env` | buildEnv of all bundled tools — for home-manager / `nix profile`. |
| `packages.${system}.odysseus-dev` | Launcher script that bootstraps a venv and runs uvicorn. |
| `apps.${system}.default` | Same launcher, exposed for `nix run`. |
| `formatter.${system}` | `nixpkgs-fmt`. |

## License

[MIT](./LICENSE).
