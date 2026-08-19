{
  description = "Odysseus dev shell — Python 3.14 + Node + system deps for local development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Supported Nix systems. nix-systems/default resolves to the four
    # platforms this flake targets (aarch64/x86_64 × linux/darwin), so the
    # multi-arch invariant is preserved without hardcoding the list here.
    systems.url = "github:nix-systems/default";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, systems, treefmt-nix, ... }:
    let
      # nixpkgs 26.11 DROPPED x86_64-darwin: `legacyPackages.x86_64-darwin`
      # now throws on eval, so `nix flake check --all-systems` fails even with
      # --no-build. `import systems` (nix-systems/default) still yields all
      # four platforms, so the list needs narrowing before genAttrs sees it.
      # CI already only covers three (the macos-13 runner was dropped in
      # 2026-06).
      #
      # Filtering (rather than hardcoding the list) keeps the `systems` input
      # and its `inputs.systems.follows` override contract intact.
      supportedSystems = nixpkgs.lib.remove "x86_64-darwin" (import systems);

      # Map a callback over every supported system, handing it the system
      # string and that system's pre-instantiated nixpkgs. Replaces
      # flake-utils.lib.eachSystem; each flake output below wraps its own
      # forEachSystem call (genAttrs yields { <system> = value; }).
      #
      forEachSystem =
        f: nixpkgs.lib.genAttrs supportedSystems (system: f system nixpkgs.legacyPackages.${system});

      # All per-system build products, computed ONCE here and projected into
      # the individual flake outputs below. Keeps the heavy let block DRY
      # instead of re-instantiating it inside every output's forEachSystem.
      perSystem = forEachSystem (
        system: pkgs:
          let
            # Multi-formatter setup (nix/shell/md/yaml) — see ./treefmt.nix.
            # Exposed as `nix fmt` and enforced by CI via the `formatting` check.
            treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

            python = pkgs.python314;

            maintainer = {
              name = "KangaZero";
              github = "KangaZero";
              email = "samuelyongw@gmail.com";
            };

            # opencv-python (cv2) runtime shared libs, mirroring the Dockerfile's
            # apt `libgl1` / `libglib2.0-0t64` / `libxcb1`. Pulled in by the
            # optional Real-ESRGAN cookbook path; cv2 dlopens libGL.so.1 /
            # libgthread-2.0.so.0 / libxcb.so.1 at import. Linux-only — Darwin
            # opencv wheels link system frameworks instead. Shared between the
            # dep closure (linuxDeps) and the runtime dlopen path (wheelLibPath)
            # so both track the Dockerfile from one edit point.
            opencvLibs = with pkgs; [ libGL glib libxcb ];

            # System-level deps mirroring the Dockerfile so `pip install -r
            # requirements.txt` can build native wheels (numpy, cryptography,
            # bcrypt, PyMuPDF, fastembed/onnxruntime, etc.) on any supported arch.
            commonDeps = with pkgs; [
              python
              python.pkgs.pip
              python.pkgs.virtualenv

              # Default LTS so downstreams using `nixpkgs.follows` aren't
              # forced onto a specific major (some pins lag the unstable tip).
              nodejs
              git
              just
              cmake
              curl
              tmux
              openssh
              pkg-config

              # Nix lint/format tooling — used by `just test` and CI.
              nixpkgs-fmt
              statix
              deadnix
              shellcheck

              # Native build chain for Python wheels that don't ship binaries
              # for every (os, arch) combination.
              stdenv.cc

              # Headers/libs commonly needed by the wheel set.
              zlib
              openssl
              libffi
              libxml2
              libxslt
              file # libmagic — dlopened by python-magic at import time
            ];

            # Linux-only extras: gosu (used by Docker entrypoint) and a couple
            # of libs that the manylinux wheels expect when building from source.
            linuxDeps = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux (with pkgs; [
              gosu
              glibcLocales
            ] ++ opencvLibs);

            # macOS: nothing extra required — the SDK frameworks are pulled in
            # automatically by stdenv on Darwin.
            # Was: darwinDeps = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ ];
            #   The isDarwin guard wrapped an empty list, so it evaluated to [ ]
            #   on every platform — a dead condition. Reduced to a plain [ ],
            #   kept as an explicit, named hook for future Darwin-only deps.
            darwinDeps = [ ];

            allDeps = commonDeps ++ linuxDeps ++ darwinDeps;

            # python-magic is deliberately absent from upstream's requirements
            # files: it resolves libmagic at *import* time, so upstream installs
            # it in the Dockerfile instead (`pip install python-magic==0.4.27`,
            # alongside apt `libmagic1`). commonDeps already ships `file`
            # (libmagic.so.1); without the Python wrapper the content-based MIME
            # sniffing in src/upload_handler.py silently degrades to extension
            # detection. Mirror the Dockerfile so `nix develop` / `nix run`
            # behave like the container. Version tracks the Dockerfile pin,
            # which is also the newest release on PyPI (0.4.27, 2022-06-07).
            # Shared by the launcher and the dev shell from one edit point; the
            # marker embeds the version, so bumping it re-installs.
            pythonMagicVersion = "0.4.27";
            installPythonMagic = ''
              MAGIC_MARKER="$VENV_DIR/.python-magic-${pythonMagicVersion}.installed"
              if [ ! -f "$MAGIC_MARKER" ]; then
                echo "installing python-magic ${pythonMagicVersion} (libmagic wrapper — a Dockerfile-only dep)…"
                pip install "python-magic==${pythonMagicVersion}" && touch "$MAGIC_MARKER" \
                  || echo "⚠  python-magic install failed — MIME sniffing falls back to file extensions" >&2
              fi
            '';

            # Runtime dlopen path for pip-installed manylinux wheels (numpy,
            # onnxruntime, PyMuPDF, etc.) — they ship binaries linked against
            # `libstdc++.so.6` / `libz.so.1` and won't find them under Nix
            # without an explicit LD_LIBRARY_PATH. Linux-only; on Darwin the
            # loader uses @rpath and this var is ignored.
            wheelLibPath = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux
              (pkgs.lib.makeLibraryPath ([
                pkgs.stdenv.cc.cc.lib
                pkgs.zlib
                pkgs.file
              ] ++ opencvLibs));

            # Aggregated environment so home-manager / `nix profile install`
            # users can pull in all the tooling with a single package.
            odysseusEnv = pkgs.buildEnv {
              name = "odysseus-env";
              paths = allDeps;
              meta = {
                description = "Odysseus dev environment — Python 3.14 + Node LTS + system deps";
                homepage = "https://github.com/KangaZero/odysseus-nix";
                maintainers = [ maintainer ];
              };
            };

            # Standalone launcher for `nix run`. Resolves a checkout (from
            # $1, $ODYSSEUS_DIR, $PWD, or an auto-managed cache clone),
            # bootstraps a venv, installs requirements.txt, and exec's uvicorn.
            # Used by apps.default below.
            odysseusDev = pkgs.writeShellApplication {
              name = "odysseus-dev";
              runtimeInputs = allDeps;
              meta = {
                description = "Launch the Odysseus FastAPI app from a local or auto-cloned checkout";
                homepage = "https://github.com/KangaZero/odysseus-nix";
                maintainers = [ maintainer ];
              };
              text = ''
                # Where to look for / clone the odysseus checkout. Override
                # the clone URL with $ODYSSEUS_REPO_URL (e.g. point at a fork).
                repo_url="''${ODYSSEUS_REPO_URL:-https://github.com/odysseus-dev/odysseus.git}"

                # Upstream odysseus develops on `dev`, which is also its default
                # branch — but it still has a stale, non-default `main`. Name the
                # branch explicitly rather than letting `git clone` follow the
                # remote's HEAD, so this can never silently start tracking `main`
                # if upstream ever flips its default. Override for forks whose
                # development branch is named differently.
                upstream_branch="''${ODYSSEUS_BRANCH:-dev}"
                cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}/odysseus-nix"
                cache_dir="$cache_root/odysseus"

                # Resolve target in order: explicit arg → $ODYSSEUS_DIR → $PWD
                # (if it looks like a checkout) → managed cache clone.
                target="''${1:-''${ODYSSEUS_DIR:-}}"
                if [ -z "$target" ]; then
                  if [ -f "$PWD/app.py" ] && [ -f "$PWD/requirements.txt" ]; then
                    target="$PWD"
                  else
                    target="$cache_dir"
                    if [ ! -d "$target" ]; then
                      echo "no odysseus checkout found — cloning $upstream_branch into $target"
                      echo "(override with: ODYSSEUS_DIR=/path/to/odysseus, or pass as arg)"
                      echo "(override branch: ODYSSEUS_BRANCH=<name>)"
                      mkdir -p "$cache_root"
                      git clone --depth 1 --branch "$upstream_branch" "$repo_url" "$target"
                    fi
                  fi
                fi

                if [ ! -f "$target/app.py" ] || [ ! -f "$target/requirements.txt" ]; then
                  echo "error: $target does not look like an odysseus checkout" >&2
                  echo "       (expected app.py and requirements.txt)" >&2
                  exit 1
                fi

                cd "$target"
                mkdir -p data logs services/cache/search

                # Make pip-installed manylinux wheels (numpy etc.) find
                # libstdc++/libz at runtime. Emitted only on Linux; on Darwin the
                # loader uses @rpath, so this is omitted entirely.
                ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
                  export LD_LIBRARY_PATH="${wheelLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                ''}

                VENV_DIR="''${VENV_DIR:-$PWD/.venv}"
                if [ -d "$VENV_DIR" ] && ! "$VENV_DIR/bin/python" --version > /dev/null 2>&1; then
                  echo "stale venv detected (Python interpreter changed) — recreating"
                  rm -rf "$VENV_DIR"
                fi
                if [ ! -d "$VENV_DIR" ]; then
                  echo "creating venv at $VENV_DIR"
                  ${python.interpreter} -m venv "$VENV_DIR"
                fi
                # shellcheck disable=SC1091
                source "$VENV_DIR/bin/activate"

                MARKER="$VENV_DIR/.requirements.installed"
                if [ ! -f "$MARKER" ] || [ "$PWD/requirements.txt" -nt "$MARKER" ]; then
                  echo "installing python deps…"
                  pip install -r requirements.txt
                  touch "$MARKER"
                fi

                ${installPythonMagic}

                REQS_OPT="$PWD/requirements-optional.txt"
                REQS_OPT_MARKER="$VENV_DIR/.requirements-optional.installed"
                if [ "''${ODYSSEUS_INSTALL_OPTIONAL:-1}" = "1" ] && [ -f "$REQS_OPT" ] \
                  && { [ ! -f "$REQS_OPT_MARKER" ] || [ "$REQS_OPT" -nt "$REQS_OPT_MARKER" ]; }; then
                  echo "installing optional python deps…"
                  pip install -r "$REQS_OPT" && touch "$REQS_OPT_MARKER"
                fi

                exec uvicorn app:app --reload --host 0.0.0.0 --port "''${APP_PORT:-7000}"
              '';
            };

            devShell = pkgs.mkShell {
              name = "odysseus-dev";

              packages = allDeps;

              shellHook = ''
                # Capture where `nix develop` was invoked from BEFORE we cd
                # elsewhere — this is (most likely) the user's odysseus-nix
                # checkout, which the fmt/lint/build recipes need to be able
                # to write to.
                export ODYSSEUS_NIX_DIR="''${ODYSSEUS_NIX_DIR:-$PWD}"

                # Quality-of-life: drop into the sibling odysseus checkout if it
                # exists. Override with ODYSSEUS_DIR=/path/to/odysseus nix develop.
                export ODYSSEUS_DIR="''${ODYSSEUS_DIR:-$ODYSSEUS_NIX_DIR/../odysseus}"

                # Make `just` work from anywhere in the shell. Prefer the user's
                # writable checkout when present (so `just fmt` etc. can write),
                # otherwise fall back to the store copy (for `nix develop
                # github:...` users who don't have a local clone).
                if [ -f "$ODYSSEUS_NIX_DIR/justfile" ]; then
                  export JUST_JUSTFILE="$ODYSSEUS_NIX_DIR/justfile"
                else
                  export JUST_JUSTFILE="${self}/justfile"
                fi

                if [ -d "$ODYSSEUS_DIR" ]; then
                  cd "$ODYSSEUS_DIR"
                else
                  echo "note: \$ODYSSEUS_DIR ($ODYSSEUS_DIR) not found — staying in $PWD"
                fi

                # Mirror the Dockerfile: the app expects data/, logs/, and the
                # search cache dir to exist before it boots (sqlite DB lives in
                # data/app.db, so a missing dir gives "unable to open database file").
                if [ -d "$ODYSSEUS_DIR" ]; then
                  mkdir -p "$ODYSSEUS_DIR/data" "$ODYSSEUS_DIR/logs" "$ODYSSEUS_DIR/services/cache/search"
                fi

                # Make pip-installed manylinux wheels (numpy etc.) find
                # libstdc++/libz at runtime. Emitted only on Linux; on Darwin the
                # loader uses @rpath, so this is omitted entirely.
                ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
                  export LD_LIBRARY_PATH="${wheelLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                ''}

                # Point Playwright (and @playwright/mcp) at the Nix-managed browser
                # store so no runtime browser downloads are needed.
                export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
                export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD="1"

                # One venv per project, inside the checkout at .venv.
                VENV_DIR="''${VENV_DIR:-$PWD/.venv}"
                if [ -d "$VENV_DIR" ] && ! "$VENV_DIR/bin/python" --version > /dev/null 2>&1; then
                  echo "stale venv detected (Python interpreter changed) — recreating"
                  rm -rf "$VENV_DIR"
                fi
                if [ ! -d "$VENV_DIR" ]; then
                  echo "creating venv at $VENV_DIR"
                  ${python.interpreter} -m venv "$VENV_DIR"
                fi
                # shellcheck disable=SC1091
                source "$VENV_DIR/bin/activate"

                # Auto-install deps when their manifests change. Markers live next
                # to the venv / node_modules so they're invalidated by a clean.
                # Opt out with ODYSSEUS_AUTO_INSTALL=0.
                if [ "''${ODYSSEUS_AUTO_INSTALL:-1}" = "1" ] && [ -d "$ODYSSEUS_DIR" ]; then
                  REQS="$PWD/requirements.txt"
                  REQS_MARKER="$VENV_DIR/.requirements.installed"
                  if [ -f "$REQS" ] && { [ ! -f "$REQS_MARKER" ] || [ "$REQS" -nt "$REQS_MARKER" ]; }; then
                    echo "installing python deps (requirements.txt changed)…"
                    pip install -r "$REQS" && touch "$REQS_MARKER" \
                      || echo "⚠  pip install failed — run \`pip install -r requirements.txt\` to retry" >&2
                  fi

                  ${installPythonMagic}

                  REQS_OPT="$PWD/requirements-optional.txt"
                  REQS_OPT_MARKER="$VENV_DIR/.requirements-optional.installed"
                  if [ "''${ODYSSEUS_INSTALL_OPTIONAL:-1}" = "1" ] && [ -f "$REQS_OPT" ] \
                    && { [ ! -f "$REQS_OPT_MARKER" ] || [ "$REQS_OPT" -nt "$REQS_OPT_MARKER" ]; }; then
                    echo "installing optional python deps (requirements-optional.txt changed)…"
                    pip install -r "$REQS_OPT" && touch "$REQS_OPT_MARKER" \
                      || echo "⚠  optional pip install failed — run \`pip install -r requirements-optional.txt\` to retry" >&2
                  fi

                  PKG="$PWD/package.json"
                  LOCK="$PWD/package-lock.json"
                  NODE_MARKER="$PWD/node_modules/.installed"
                  if [ -f "$PKG" ] && { [ ! -d "$PWD/node_modules" ] || [ ! -f "$NODE_MARKER" ] \
                    || [ "$PKG" -nt "$NODE_MARKER" ] \
                    || { [ -f "$LOCK" ] && [ "$LOCK" -nt "$NODE_MARKER" ]; }; }; then
                    echo "installing node deps (package.json/lock changed)…"
                    npm install && touch "$NODE_MARKER" \
                      || echo "⚠  npm install failed — run \`npm install\` to retry" >&2
                  fi
                fi

                echo ""
                echo "odysseus dev shell ready (${system})"
                echo "  python:  $(python --version)"
                echo "  node:    $(node --version)"
                echo "  venv:    $VENV_DIR"
                echo ""
                echo "run:   uvicorn app:app --reload --port 7000   (or: just dev)"
              '';
            };

            # Opt-in variant of the dev shell that also provisions a chromium
            # binary for odysseus' built-in Browser MCP server (`npx
            # @playwright/mcp`). Upstream's Dockerfile installs apt `chromium`;
            # the app resolves a browser via ODYSSEUS_BROWSER_EXECUTABLE (or
            # `chromium` on PATH) and passes it to Playwright as
            # `--executable-path` — it force-overrides PLAYWRIGHT_BROWSERS_PATH,
            # so the shell's playwright-driver bundle can't satisfy the MCP.
            # chromium is a ~1.7 GiB, Linux-only closure, so rather than bloat
            # every default shell it lives here, entered explicitly with
            # `nix develop .#browser`. Darwin has no nixpkgs chromium → this
            # shell is Linux-only (null, and omitted from devShells, elsewhere).
            browserShell =
              if pkgs.stdenv.hostPlatform.isLinux then
                devShell.overrideAttrs
                  (prev: {
                    nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.chromium ];
                    shellHook = prev.shellHook + ''
                      export ODYSSEUS_BROWSER_EXECUTABLE="${pkgs.chromium}/bin/chromium"
                      echo "  browser: $ODYSSEUS_BROWSER_EXECUTABLE (built-in Browser MCP enabled)"
                    '';
                  })
              else
                null;
          in
          {
            inherit treefmtEval odysseusEnv odysseusDev devShell browserShell;
          }
      );
    in
    {
      devShells = forEachSystem (
        system: _pkgs:
          {
            default = perSystem.${system}.devShell;
          }
          # `nix develop .#browser` — default shell + chromium for the built-in
          # Browser MCP. Linux-only (browserShell is null on Darwin).
          // nixpkgs.lib.optionalAttrs (perSystem.${system}.browserShell != null) {
            browser = perSystem.${system}.browserShell;
          }
      );

      # Packages — used by home-manager / `nix profile install` consumers.
      #   packages.default     — alias for odysseus-env
      #   packages.odysseus-env — buildEnv with all the tooling
      #   packages.odysseus-dev — the launcher script (also exposed as apps.default)
      packages = forEachSystem (system: _pkgs: {
        default = perSystem.${system}.odysseusEnv;
        odysseus-env = perSystem.${system}.odysseusEnv;
        odysseus-dev = perSystem.${system}.odysseusDev;
      });

      # `nix run github:KangaZero/odysseus-nix [-- /path/to/checkout]`
      apps = forEachSystem (system: _pkgs: {
        default = {
          type = "app";
          program = "${perSystem.${system}.odysseusDev}/bin/odysseus-dev";
          meta = {
            description = "Launch the Odysseus FastAPI app from a local or auto-cloned checkout";
            homepage = "https://github.com/KangaZero/odysseus-nix";
            maintainers = perSystem.${system}.odysseusDev.meta.maintainers;
          };
        };
      });

      # `nix fmt` runs treefmt across the whole tree (nix/shell/md/yaml).
      formatter = forEachSystem (system: _pkgs: perSystem.${system}.treefmtEval.config.build.wrapper);

      # `nix flake check` (and `just check`) enforce formatting in CI.
      checks = forEachSystem (system: _pkgs: {
        formatting = perSystem.${system}.treefmtEval.config.build.check self;
      });
    };
}
