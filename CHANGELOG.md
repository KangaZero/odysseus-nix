# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`main` is a rolling branch that clones upstream `dev` HEAD (no rev pin);
release branches/tags (`vX.Y.Z`) bake in a pinned upstream `odysseusRev` and
sync the managed cache clone to it.

## [Unreleased]

## [1.0.0] - 2026-08-19

First stable release. The flake's interface — outputs, env knobs, and the
release-branch rev-pinning contract — is considered settled; breaking changes to
it now warrant a major bump.

### Added

- Auto-install `python-magic==0.4.27` in **both** the `nix run` launcher and the
  dev shell. The package is in none of upstream's requirements files: it resolves
  `libmagic` at import time, so upstream installs it in the `Dockerfile` only.
  `commonDeps` already shipped `file` (`libmagic.so.1`), but without the Python
  wrapper the content-based MIME sniffing in `src/upload_handler.py` silently
  degraded to extension detection here. The install is shared between the two
  call sites from one definition, marker-guarded at
  `$VENV_DIR/.python-magic-<version>.installed` (so bumping the version
  re-installs), and non-fatal — a failure warns and startup continues. The pinned
  version tracks the Dockerfile and is also the newest release on PyPI
  (0.4.27, 2022-06-07).

### Changed

- Lead `README.md` with an `> [!IMPORTANT]` disclaimer that upstream Odysseus
  development has **moved to the `dev` branch** — `dev` is upstream's default
  branch and everything from it onwards is what this flake tracks; upstream's
  `main` still exists but is not where development happens, so it must not be
  pinned. The note also records the organisation transfer from
  `pewdiepie-archdaemon` to `odysseus-dev`.
- Re-pin upstream `odysseusRev` `43682d4` → `5c83501` (live `dev` HEAD). Drift is
  a single app-level commit (`fix(time): prefer IANA timezone name over offset`);
  `Dockerfile`, `requirements.txt`, `requirements-optional.txt`, `package.json`,
  `package-lock.json` and `pyproject.toml` are all byte-identical, so there are no
  dep changes.

## [0.8.0] - 2026-08-19

### Removed

- **`x86_64-darwin` (Intel Mac) support.** nixpkgs 26.11 dropped the platform:
  `legacyPackages.x86_64-darwin` now throws during _evaluation_, which broke
  `nix flake check --all-systems` even with `--no-build`. `forEachSystem` maps
  over `lib.remove "x86_64-darwin" (import systems)` instead of the raw
  `nix-systems/default` list, so the flake targets `x86_64-linux`,
  `aarch64-linux`, and `aarch64-darwin`. Filtering (rather than hardcoding the
  list) keeps the `systems` input and its `inputs.systems.follows` override
  contract. CI is unaffected — there has been no `macos-13` leg since
  2026-06. Intel Macs need a nixpkgs pinned to `nixpkgs-26.05-darwin`, which
  receives security fixes until the end of 2026.

### Fixed

- Replace the deprecated `stdenv.isLinux` / `stdenv.isDarwin` shorthands with
  `stdenv.hostPlatform.isLinux` / `.isDarwin`. nixpkgs 26.11 emits
  `evaluation warning: stdenv.isLinux is deprecated` for the old spelling.

### Changed

- Restructure `README.md` along the [Doom Emacs][doom-readme] README
  conventions (centred header with badges, table of contents, GFM
  admonitions, reference-style links) and correct six stale claims:
  `ODYSSEUS_INSTALL_OPTIONAL` is honoured by the launcher too, not just the
  dev shell; `playwright-driver.browsers` is a dev-shell env var and is **not**
  in the `odysseus-env` closure; `python-magic` is installed by upstream's
  Dockerfile only and appears in no requirements file, so MIME sniffing
  degrades to extension detection here; `checks.<system>.formatting`,
  `ODYSSEUS_BROWSER_EXECUTABLE`, `ODYSSEUS_REV`, `ODYSSEUS_NO_SYNC` and
  `just clean` were undocumented in their tables.
- Bump `flake.lock`: nixpkgs `d407951` (2026-07-05) → `0ae2bc1` (2026-08-18),
  moving the unstable channel to 26.11 (`python314` 3.14.4 → 3.14.7, `nodejs`
  24.19.0); treefmt-nix `db94781` (2026-05-31) → `27b3b12` (2026-08-16). The
  `systems` input was already at its tip.
- Re-pin upstream `odysseusRev` `d8a2059` → `43682d4` (live `dev` HEAD). The
  115-commit drift is app-level: `Dockerfile`, `package.json`,
  `package-lock.json`, and `pyproject.toml` are byte-identical, so the
  Dockerfile-mirrored system dep set is untouched. `requirements.txt` constrains
  `mcp` to `<2` (the SDK v2 rewrite is breaking) and `requirements-optional.txt`
  adds `kokoro` + `soundfile` gated to `python_version >= "3.11" and < "3.13"` —
  this flake ships Python 3.14, so pip skips both and no new native deps are
  needed.

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

[doom-readme]: https://github.com/doomemacs/doomemacs/blob/master/README.md
[Unreleased]: https://github.com/KangaZero/odysseus-nix/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.8.0...v1.0.0
[0.8.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/KangaZero/odysseus-nix/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/KangaZero/odysseus-nix/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/KangaZero/odysseus-nix/releases/tag/v0.1.0
