# odysseus-nix

Nix flake providing a reproducible dev shell for [Odysseus](https://github.com/pewdiepie-archdaemon/odysseus).

Supports:

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin` (Intel Mac)
- `aarch64-darwin` (Apple Silicon)

## Usage

Requires Nix with flakes enabled (`experimental-features = nix-command flakes`).

```sh
# Sibling layout (default): ../odysseus next to this folder.
nix develop

# Or point at a custom checkout:
ODYSSEUS_DIR=/path/to/odysseus nix develop
```

The shell:

1. `cd`s into `$ODYSSEUS_DIR` if it exists.
2. Creates/activates `.venv/` inside that checkout.
3. Leaves you to run the recipes below (or `pip install -r requirements.txt` + `uvicorn app:app --reload --port 7000` directly).

## Just recipes

A [`justfile`](./justfile) ships alongside the flake. From this folder, after `nix develop`:

```sh
just                  # list all recipes
just install          # pip install -r requirements.txt
just install-optional # pip install -r requirements-optional.txt
just install-node     # npm install
just install-all      # install + install-node
just run              # uvicorn app:app --reload --host 0.0.0.0 --port $APP_PORT
just dev              # alias for `run`
just test [args...]   # pytest, with optional args (e.g. `just test -k auth`)
just docker-up        # docker compose up --build -d
just docker-down      # docker compose down
just docker-logs      # docker compose logs -f
just fmt              # nix fmt
just check            # nix flake check
just lock-update      # nix flake update
just info             # print resolved paths + versions
```

All recipes operate on `$ODYSSEUS_DIR` (defaulted to `../odysseus`). `APP_PORT` overrides the dev-server port.

> Run `just` from inside this `odysseus-nix/` folder, not from the odysseus checkout — the devShell auto-cds into odysseus, so use `just -f ~/Documents/odysseus-nix/justfile <recipe>` from there, or just open a separate shell in this folder.

## direnv

If you use [direnv](https://direnv.net/), this folder ships a `.envrc` (`use flake`). Run `direnv allow` once and the shell auto-loads.

## What's included

System-level deps mirror the project Dockerfile so native Python wheels build cleanly:

- Python 3.12 + pip + virtualenv
- Node.js 26 (for the optional Browser MCP server)
- just (task runner — see recipes above)
- git, cmake, curl, tmux, openssh, pkg-config
- zlib, openssl, libffi, libxml2/xslt (wheel build headers)
- gosu (Linux only — used by the Docker entrypoint)

Python packages themselves are installed via `pip` into the venv, not Nix — keeps the flake small and avoids fighting nixpkgs over PyPI versions like `chromadb-client` and `fastembed`.
