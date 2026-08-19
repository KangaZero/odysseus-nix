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

| File        | Purpose                                                  |
| ----------- | -------------------------------------------------------- |
| `flake.nix` | The whole flake — devShell, packages, `nix run` launcher |
| `justfile`  | Dev task recipes (`just dev`, `just test`, etc.)         |

## Invariants to preserve

- **Fully hands-off**: entering `nix develop` (or `nix run`) must require zero manual steps. Auto-install pip + npm deps on manifest change; create `data/`, `logs/`, `services/cache/search/` automatically.
- **Opt-out, not opt-in**: automation is on by default. Escape hatches use env vars (`ODYSSEUS_AUTO_INSTALL=0`, `ODYSSEUS_INSTALL_OPTIONAL=1`).
- **`just` works anywhere**: `JUST_JUSTFILE` is exported so recipes run after the auto-cd into odysseus.
- **Multi-arch**: the flake targets three platforms (`x86_64-linux`, `aarch64-linux`, `aarch64-darwin`), one native CI runner each. `x86_64-darwin` is filtered out of the `systems` list — nixpkgs 26.11 dropped the platform and `legacyPackages.x86_64-darwin` throws on eval. Test changes with `just test`.

## How to test changes

The gate is `just test` (run inside the shell):

```sh
nix develop --command just test   # fmt-check + lint + flake check + build — the real gate
nix develop                       # smoke-test the shell end-to-end
nix run -- [/path]                # test the standalone launcher
```

Note: bare `nix flake check` only builds/runs the **native** system's checks. `just check` additionally evaluates every supported system via `--all-systems --no-build` (eval-only, no cross-build).

## Custom commands

- `/slave-on` — restore the full project savepoint (repos, working rules, the pinned-upstream-commit check, architecture facts, work log) so iteration continues without re-discovery.
- `/continue` — pull the latest odysseus repo, reconcile the flake with any new deps/dirs, verify the shell still works, and suggest improvements.
