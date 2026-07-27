# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`main` is a rolling branch that clones upstream `dev` HEAD (no rev pin);
release branches/tags (`vX.Y.Z`) bake in a pinned upstream `odysseusRev` and
sync the managed cache clone to it.

## [Unreleased]

## [0.7.0] - 2026-07-27

### Added

- `nix develop .#browser` — an opt-in dev shell that adds `chromium` and sets
  `ODYSSEUS_BROWSER_EXECUTABLE` for odysseus' built-in Browser MCP server
  (`npx @playwright/mcp`). Upstream's Dockerfile now installs apt `chromium`;
  the app resolves the browser via `ODYSSEUS_BROWSER_EXECUTABLE`/PATH and
  overrides `PLAYWRIGHT_BROWSERS_PATH`, so the existing playwright-driver
  bundle can't satisfy it. `chromium` is a ~1.7 GiB, Linux-only closure, so it
  lives in this opt-in shell rather than bloating the default one. Linux-only.

### Changed

- Set `meta` inline on the `odysseus-env` (`buildEnv`) and `odysseus-dev`
  (`writeShellApplication`) derivations instead of via a trailing
  `.overrideAttrs`. Both builders forward `meta` directly, so the wrapper was
  legacy boilerplate.
- Point the launcher's default clone URL at `odysseus-dev/odysseus` (upstream
  transferred orgs from `pewdiepie-archdaemon`). The old URL still redirects;
  this tracks the canonical location.
- Re-pin upstream `odysseusRev` `28d27ee` → `d8a2059` (live `dev` HEAD). The
  drift added apt `chromium` for the Browser MCP (handled by the new `.#browser`
  shell) and the org transfer; `requirements*.txt`, `package-lock.json`, and
  `pyproject.toml` are byte-identical, so no Python/Node dep changes.

## [0.6.0] - 2026-07-17

### Changed

- Drop the `flake-utils` input in favour of `nix-systems/default` + a
  `genAttrs`-based `forEachSystem` helper (mirrors the ClaudeNixWrapper flake
  structure). System iteration now uses `nixpkgs.legacyPackages.${system}`
  instead of a per-system `import nixpkgs`. Per-system build products
  (`devShell`, `odysseusEnv`, `odysseusDev`, `treefmtEval`) are computed once
  in a `perSystem` attrset and projected into each output, keeping the shared
  logic DRY. Supported platforms are unchanged — `nix-systems/default`
  resolves to the same four (`{aarch64,x86_64}-{linux,darwin}`).
- Re-pin upstream `odysseusRev` to `28d27ee` (2 commits ahead of v0.5.0's
  `c1d6287`: an Arch NVIDIA Docker docs page and an importer SSRF fix — no
  Dockerfile/requirements/package changes, so the flake is otherwise
  untouched).

## [0.5.0] - 2026-07-14

### Changed

- Re-pin upstream `odysseusRev` to `c1d6287`. Cut from current `main`, so it
  carries the newer launcher/shellHook fixes (`ODYSSEUS_INSTALL_OPTIONAL` in
  the launcher, pip/npm install-failure messages, `ODYSSEUS_NIX_DIR` export).
  Pin apparatus byte-identical to v0.4.0.

## [0.4.0] - 2026-07-06

### Changed

- Re-pin upstream `odysseusRev` to `2826dcf`.

## [0.3.1] - 2026-06-29

### Changed

- Re-pin upstream `odysseusRev` to `893e490` (pure re-pin, flake otherwise
  untouched).

## [0.3.0] - 2026-06-26

### Changed

- Bump `python312` → `python314` and add opencv/cv2 runtime libs
  (`libGL`/`glib`/`libxcb`) to both the Linux dep closure and the wheel
  `LD_LIBRARY_PATH`, mirroring upstream's move to `python:3.14-slim`.
- Bump the `nixpkgs` lock.
- Re-pin upstream `odysseusRev` to `de12d47`.

## [0.2.0] - 2026-06-12

### Added

- Adopt treefmt-nix (nixpkgs-fmt + shfmt + prettier) as the formatter, with a
  `checks.formatting` gate enforced in CI.
- `just clean` recipe to remove `.venv` / `node_modules` (forces reinstall).

### Changed

- Expand CI to all four Nix systems.
- Re-pin upstream `odysseusRev` to `9d7a3d6`.

### Fixed

- Re-enable shellcheck on the launcher; move the Linux `LD_LIBRARY_PATH`
  export behind an `isLinux` guard (SC2157).

## [0.1.0] - 2026-06-01

### Added

- Initial flake: hands-off dev shell (Python 3.14 + Node LTS + Dockerfile-
  mirrored system deps), `nix run` launcher, and multi-arch platform
  declarations. Pins upstream `odysseusRev` `e5b9275`.

[Unreleased]: https://github.com/KangaZero/odysseus-nix/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/KangaZero/odysseus-nix/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/KangaZero/odysseus-nix/releases/tag/v0.1.0
