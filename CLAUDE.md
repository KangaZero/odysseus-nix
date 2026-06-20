# odysseus-nix — Claude Code context

## What this repo is

A Nix flake that wraps the [odysseus](https://github.com/pewdiepie-archdaemon/odysseus) FastAPI app in a reproducible, fully hands-off dev shell. It is intentionally kept separate from the odysseus repo itself.

## Repo layout

```
odysseus-nix/   ← this repo (the flake)
odysseus/       ← sibling checkout (the actual app)
```

The shell auto-cds into `$ODYSSEUS_DIR` (default `../odysseus`) on entry.

## Key files

| File | Purpose |
|------|---------|
| `flake.nix` | The whole flake — devShell, packages, `nix run` launcher |
| `justfile` | Dev task recipes (`just dev`, `just test`, etc.) |

## Invariants to preserve

- **Fully hands-off**: entering `nix develop` (or `nix run`) must require zero manual steps. Auto-install pip + npm deps on manifest change; create `data/`, `logs/`, `services/cache/search/` automatically.
- **Opt-out, not opt-in**: automation is on by default. Escape hatches use env vars (`ODYSSEUS_AUTO_INSTALL=0`, `ODYSSEUS_INSTALL_OPTIONAL=1`).
- **`just` works anywhere**: `JUST_JUSTFILE` is exported so recipes run after the auto-cd into odysseus.
- **Multi-arch**: all four platforms (`x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`). Test changes with `nix flake check`.

## How to test changes

```sh
nix flake check          # syntax + eval across all systems
nix develop              # smoke-test the shell end-to-end
nix run -- [/path]       # test the standalone launcher
```

## Custom commands

- `/continue` — pull the latest odysseus repo, reconcile the flake with any new deps/dirs, verify the shell still works, and suggest improvements.
