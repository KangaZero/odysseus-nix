# /continue — upstream sync pass

Use after `/slave-on` (which restores session context). This command pulls upstream, reconciles deps, smoke-tests the shell, and surfaces improvements. Work through steps in order:

## 1 — Pull latest odysseus

```sh
cd ../odysseus && git pull --ff-only
```

If the pull fails (diverged history), report it and stop.

## 2 — Reconcile deps and directories

- Check `requirements.txt` and `requirements-optional.txt` for new packages that might need system-level headers in `flake.nix` (e.g. new native-extension packages like `cryptography`, `lxml`, `Pillow`).
- Check `package.json` for new Node deps that might need a newer Node version.
- Check the `Dockerfile` for any new `RUN mkdir -p …` lines — the shellHook must mirror these so the app boots without manual setup.
- If `flake.nix` needs changes, make them and run `nix flake check` to verify.

## 3 — Smoke-test the shell

```sh
nix develop --command bash -c '
  echo "--- just ---"; just --list || echo "FAIL"
  echo "--- dirs ---"; ls -d data logs services/cache/search || echo "FAIL"
  echo "--- import ---"; python -c "import app; print(\"ok\")" || echo "FAIL"
'
```

Report pass/fail for each check.

## 4 — Suggest improvements (pick 1–3 that are genuinely relevant)

Look at the following and surface any that apply — be specific, not generic:

- **Version bumps**: is `python312` still current? Is there a newer LTS Node in nixpkgs (`nodejs_22` → `nodejs_24`)?
- **nixpkgs channel**: is `nixos-unstable` appropriate, or would `nixos-24.11` / `nixos-25.05` be more stable for this use case?
- **flake.lock staleness**: check `git log --oneline flake.lock | head -1` to see last update. Report the date and suggest `nix flake update` if warranted — treat as advisory, not a hard flag.
- **Package alternatives**: e.g. `uv` instead of `pip` for faster installs, `bun` instead of `npm`, `ruff` for linting.
- **Release**: if there have been ≥ 3 meaningful commits since the last git tag, suggest tagging a new version (`git tag vX.Y`).
- **CI**: does the repo have a GitHub Actions workflow? If not, offer to add one that runs `nix flake check`.
- **direnv**: is `.envrc` present and correct? Does it need `nix_direnv_watch_file flake.lock`?

Only raise items with a concrete recommendation — skip anything vague.
