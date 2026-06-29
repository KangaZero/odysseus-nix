# /slave-on — odysseus-nix project savepoint

You are resuming work on **odysseus-nix**. Load this context, then **run the
upstream-commit check (below) before doing anything else**, and report status.

## Repos (both are real, local, git)

| Path                       | What                                             | Remote                                                 | Default branch |
| -------------------------- | ------------------------------------------------ | ------------------------------------------------------ | -------------- |
| `~/Documents/odysseus-nix` | THE flake (what you maintain)                    | `git@github.com:KangaZero/odysseus-nix.git`            | `main`         |
| `~/Documents/odysseus`     | upstream app (reference only — read, don't edit) | `https://github.com/pewdiepie-archdaemon/odysseus.git` | `dev`          |

odysseus-nix provides a reproducible dev env (Python 3.14 + Node LTS + system
deps) for the odysseus app. `main` is **rolling** (clones upstream `dev` HEAD,
no rev pin). **Release branches** (`v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.3.1`, …)
**bake in a pinned upstream rev** and auto-sync the managed cache clone to it.
Active release branch = **`v0.3.0`** (pins `de12d47`). Tag `v0.3.1` exists on
`main`; its release branch (pinning `893e490`) is **pending**.

## Working rules (HARD — from the user, do not deviate)

1. **Consult before every change.** Propose → get approval → apply. Do not
   batch-apply unapproved edits. Revert to HEAD if asked to reset.
2. **Verify against real sources; never hallucinate.** Confirm every claim
   against the real Dockerfile / requirements / remote refs. When you cite a
   fact, you must have checked it this session.
3. **Always run real tests.** The gate is `nix develop --command just test`
   (= `fmt-check` + `lint` [statix/deadnix/shellcheck] + `nix flake check
--all-systems` + `nix build .#default .#odysseus-dev`). Must print
   `✅ all checks passed`. For launcher changes, also functionally verify
   (build `.#odysseus-dev`, run it against a temp `XDG_CACHE_HOME`, confirm the
   checked-out rev).
4. **Modern, stable syntax only.** No deprecated patterns. TypeScript-style
   rigor applied to Nix/bash.
5. **System deps must keep mirroring the Dockerfile.** Whenever upstream's
   `Dockerfile` apt list changes, re-check `commonDeps`/`linuxDeps` in
   `flake.nix` still cover it. (Currently a superset — VALID. The opencv/cv2
   runtime libs `libgl1`/`libglib2.0-0t64`/`libxcb1` are mirrored as the
   linux-only `opencvLibs` = `[ libGL glib libxcb ]`, shared between
   `linuxDeps` and `wheelLibPath`.)
6. **Versioning: default minor bump.** Routine releases increment the minor
   version (`v0.X.0`). Only cut a major version (`v1.0.0`) for breaking /
   architectural changes. Patch versions (`v0.x.Y`) are for hotfixes on an
   already-cut release branch only.
7. **All commits authored by `KangaZero <samuelyongw@gmail.com>`.** No Claude
   co-author footer. Verify with `git config user.name` / `user.email` before
   committing.

## Upstream-commit check — RUN THIS EACH TIME (user directive: "always check this commit")

```sh
# live upstream dev HEAD (the real source of truth):
git ls-remote https://github.com/pewdiepie-archdaemon/odysseus.git refs/heads/dev
# rev currently pinned in the latest release branch (v0.3.0):
git -C ~/Documents/odysseus-nix show v0.3.0:flake.nix | grep -m1 odysseusRev
```

If the live `dev` HEAD differs from the pinned `odysseusRev`, upstream has
drifted → a new release branch (re-pinned) may be warranted. Confirm with the
user before cutting one.

## Architecture facts

- **`flake.nix`** exposes: `devShells.default` (interactive `nix develop`),
  `packages.{default,odysseus-env,odysseus-dev}`, `apps.default` (the
  `nix run` launcher = `odysseus-dev`), `formatter` (treefmt), and
  `checks.formatting`.
- **`odysseus-dev` launcher**: resolves a checkout (arg → `$ODYSSEUS_DIR` →
  `$PWD` if it looks like a checkout → managed cache clone), bootstraps a venv,
  `pip install`s, exec's `uvicorn app:app --reload` on port 7000. On release
  branches it also pins/syncs the cache clone to `odysseusRev` (override with
  `ODYSSEUS_REV=<sha>`; opt out of sync with `ODYSSEUS_NO_SYNC=1`).
- **Stale venv guard**: shellHook and launcher both probe
  `$VENV_DIR/bin/python --version` before activating; if the probe fails (e.g.
  after a Python upgrade), the venv is `rm -rf`'d and recreated automatically.
- **Maintainer metadata**: `maintainer = { name="KangaZero"; github="KangaZero"; email="samuelyongw@gmail.com"; }` is defined in `flake.nix` and threaded into `meta.maintainers` on `odysseusEnv`, `odysseusDev`, and `apps.default`.
- **Formatting** is treefmt-nix (`./treefmt.nix`): `nixpkgs-fmt` (nix),
  `shfmt` (shell incl. `.githooks/pre-push`), `prettier` (md/yaml). `nix fmt`
  formats; `just fmt-check` runs `nix fmt -- --ci`; enforced in CI via
  `checks.formatting`.
- **Env knobs**: `ODYSSEUS_DIR`, `ODYSSEUS_REPO_URL`, `ODYSSEUS_REV`
  (release-only), `ODYSSEUS_NO_SYNC` (release-only), `ODYSSEUS_AUTO_INSTALL`,
  `ODYSSEUS_INSTALL_OPTIONAL`, `APP_PORT` (default 7000), `VENV_DIR`,
  `XDG_CACHE_HOME`.
- **CI** (`.github/workflows/ci.yml`): runs `nix develop --command just test`
  on a **3-runner** matrix: `ubuntu-latest`→x86_64-linux,
  `ubuntu-24.04-arm`→aarch64-linux, `macos-latest`→aarch64-darwin.
  Required check names: `test (ubuntu-latest)`, `test (ubuntu-24.04-arm)`,
  `test (macos-latest)`. **`macos-13` (x86_64-darwin) dropped** — runner
  unretrievable + nixpkgs sunsetting x86_64-darwin in 26.05.
  `nix-installer-action@main` intentionally unpinned (user vetoed pinning).
- **`just check` gotcha**: `nix flake check --all-systems` BUILDS every
  system's `checks` → fails on a runner that can't cross-build. Recipe runs
  native `nix flake check` (build+run) PLUS `--all-systems --no-build` (eval
  only). Never re-add `--all-systems` as a build pass.
- **Auto-install markers** (`.requirements.installed` etc.) live inside
  `.venv` / `node_modules`; `just clean` removes those dirs to force reinstall.
- **`apps.default.meta`**: has `description`, `homepage`, and `maintainers` —
  silences the `nix flake check` warning that fired on all 4 systems before.
- **`.envrc`**: `use flake` + `nix_direnv_watch_file flake.lock` — direnv
  auto-reloads on `nix flake update` without manual `direnv reload`.

## Work log / savepoint

- **2026-06-12 maintenance pass** (Opus 4.8). History rewritten + force-pushed
  to fix wrong author. Key commits: shellcheck re-enabled on launcher (SC2157
  fix), treefmt-nix adopted, `just check` split into native + `--all-systems
--no-build`, CI expanded to 4 systems. Released `v0.2.0` pinning `9d7a3d6`.
- **2026-06-26 pass** (Sonnet 4.6). Reconciled web-UI changes + upstream drift.
  Bumped nixpkgs lock, `python312`→`python314`, added `opencvLibs` to
  `linuxDeps` + `wheelLibPath`. Dropped dead `macos-13` CI leg. Released
  **`v0.3.0`** pinning `de12d4734a1705a4f309cb1df7ee0c095b8abef0`.
- **2026-06-29 pass** (Sonnet 4.6). Pulled 167-file upstream update
  (`de12d47`→`893e490`). Key changes to `main` (all on tag `v0.3.1`,
  pushed to origin):
  - `ef248b2` fix(flake): stale venv detection in shellHook + launcher —
    probes `$VENV_DIR/bin/python --version`, rm + recreates if broken.
    Also adds `meta.description` to `apps.default` (silences 4-system warning).
  - `ce3ced4` fix(direnv): `nix_direnv_watch_file flake.lock` added to `.envrc`.
  - `9417237` feat(flake): maintainer metadata (`KangaZero / samuelyongw@gmail.com`)
    threaded into `odysseusEnv`, `odysseusDev`, `apps.default` via `overrideAttrs`.
  - `aa8d5cd` docs(readme): bump release examples to v0.3.1, note direnv watch.
  - `/slave-on` moved into repo as `.claude/commands/slave-on.md` (portable
    across machines).
  - **User vetoes**: do NOT switch the flake's nix formatter away from
    nixpkgs-fmt unprompted; do NOT pin `nix-installer-action`.
  - **New versioning rule**: default minor bump (`v0.X.0`); major only for
    breaking changes; patch only for hotfixes on existing release branch.

## Pending

- **`v0.3.1` release branch** pinning `893e490cdccf8a2a16a5fd3241ca9facfe2a3968`
  (live upstream `dev` HEAD as of 2026-06-29). Not yet cut — confirm with user.
- **GitHub branch protection on `main`**: blocked (no `GH_TOKEN` in agent
  shell). Required checks: `test (ubuntu-latest)`, `test (ubuntu-24.04-arm)`,
  `test (macos-latest)`; strict; block force-push + deletion. Do via web UI or
  `export GH_TOKEN=$(gh auth token)` first.

## On invocation

1. Run the upstream-commit check and report drift.
2. `cd ~/Documents/odysseus-nix && git fetch && git status` — report branch +
   how it relates to `origin`.
3. Summarize pending items above and ask what to work on.

Do NOT auto-run mutating commands (push, branch cuts, rm) without explicit approval.
