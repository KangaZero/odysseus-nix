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
3. Leaves you to run `pip install -r requirements.txt` and `uvicorn app:app --reload --port 7000`.

## direnv

If you use [direnv](https://direnv.net/), this folder ships a `.envrc` (`use flake`). Run `direnv allow` once and the shell auto-loads.

## What's included

System-level deps mirror the project Dockerfile so native Python wheels build cleanly:

- Python 3.12 + pip + virtualenv
- Node.js 20 (for the optional Browser MCP server)
- git, cmake, curl, tmux, openssh, pkg-config
- zlib, openssl, libffi, libxml2/xslt (wheel build headers)
- gosu (Linux only — used by the Docker entrypoint)

Python packages themselves are installed via `pip` into the venv, not Nix — keeps the flake small and avoids fighting nixpkgs over PyPI versions like `chromadb-client` and `fastembed`.
