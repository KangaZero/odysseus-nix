{
  description = "Odysseus dev shell — Python 3.12 + Node + system deps for local development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, treefmt-nix, ... }:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ]
      (system:
        let
          pkgs = import nixpkgs { inherit system; };

          # Multi-formatter setup (nix/shell/md/yaml) — see ./treefmt.nix.
          # Exposed as `nix fmt` and enforced by CI via the `formatting` check.
          treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

          python = pkgs.python312;

          # Pinned upstream odysseus revision shipped with this flake tag.
          # Bump this (and the flake's own git tag) when cutting a new release.
          # Users can still override at runtime via ODYSSEUS_REV=<sha>.
          odysseusRev = "9d7a3d66c07dc0bb5cf0a894022b4b6b4eada454";

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
          ];

          # Linux-only extras: gosu (used by Docker entrypoint) and a couple
          # of libs that the manylinux wheels expect when building from source.
          linuxDeps = pkgs.lib.optionals pkgs.stdenv.isLinux (with pkgs; [
            gosu
            glibcLocales
          ]);

          # macOS: nothing extra required — the SDK frameworks are pulled in
          # automatically by stdenv on Darwin.
          # Was: darwinDeps = pkgs.lib.optionals pkgs.stdenv.isDarwin [ ];
          #   The isDarwin guard wrapped an empty list, so it evaluated to [ ]
          #   on every platform — a dead condition. Reduced to a plain [ ],
          #   kept as an explicit, named hook for future Darwin-only deps.
          darwinDeps = [ ];

          allDeps = commonDeps ++ linuxDeps ++ darwinDeps;

          # Runtime dlopen path for pip-installed manylinux wheels (numpy,
          # onnxruntime, PyMuPDF, etc.) — they ship binaries linked against
          # `libstdc++.so.6` / `libz.so.1` and won't find them under Nix
          # without an explicit LD_LIBRARY_PATH. Linux-only; on Darwin the
          # loader uses @rpath and this var is ignored.
          wheelLibPath = pkgs.lib.optionalString pkgs.stdenv.isLinux
            (pkgs.lib.makeLibraryPath [
              pkgs.stdenv.cc.cc.lib
              pkgs.zlib
            ]);

          # Aggregated environment so home-manager / `nix profile install`
          # users can pull in all the tooling with a single package.
          odysseusEnv = pkgs.buildEnv {
            name = "odysseus-env";
            paths = allDeps;
          };

          # Standalone launcher for `nix run`. Resolves a checkout (from
          # $1, $ODYSSEUS_DIR, $PWD, or an auto-managed cache clone),
          # bootstraps a venv, installs requirements.txt, and exec's uvicorn.
          # Used by apps.default below.
          odysseusDev = pkgs.writeShellApplication {
            name = "odysseus-dev";
            runtimeInputs = allDeps;
            text = ''
              # Where to look for / clone the odysseus checkout. Override
              # the clone URL with $ODYSSEUS_REPO_URL (e.g. point at a fork).
              repo_url="''${ODYSSEUS_REPO_URL:-https://github.com/pewdiepie-archdaemon/odysseus.git}"
              cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}/odysseus-nix"
              cache_dir="$cache_root/odysseus"
              # Pinned upstream rev baked in at flake-eval time. Override
              # via ODYSSEUS_REV=<sha> (must be a full SHA — branches/tags
              # need a SHA resolve and aren't supported here).
              pinned_rev="''${ODYSSEUS_REV:-${odysseusRev}}"

              # Resolve target in order: explicit arg → $ODYSSEUS_DIR → $PWD
              # (if it looks like a checkout) → managed cache clone.
              target="''${1:-''${ODYSSEUS_DIR:-}}"
              user_managed=0
              if [ -z "$target" ]; then
                if [ -f "$PWD/app.py" ] && [ -f "$PWD/requirements.txt" ]; then
                  target="$PWD"
                  user_managed=1
                else
                  target="$cache_dir"
                fi
              else
                user_managed=1
              fi

              # Only sync the managed cache clone to the pinned rev. User-
              # supplied checkouts ($ODYSSEUS_DIR, $PWD, arg) are left alone
              # so local work-in-progress isn't clobbered.
              if [ "$user_managed" = "0" ]; then
                if [ ! -d "$target/.git" ]; then
                  echo "cloning odysseus into $target (pinned $pinned_rev)"
                  echo "(override location: ODYSSEUS_DIR=/path/to/odysseus)"
                  echo "(override rev:      ODYSSEUS_REV=<sha>)"
                  mkdir -p "$cache_root"
                  rm -rf "$target"
                  git init -q "$target"
                  git -C "$target" remote add origin "$repo_url"
                  git -C "$target" fetch --depth 1 origin "$pinned_rev"
                  git -C "$target" checkout --detach FETCH_HEAD
                elif [ "''${ODYSSEUS_NO_SYNC:-0}" != "1" ]; then
                  current_rev="$(git -C "$target" rev-parse --verify HEAD 2>/dev/null || true)"
                  if [ "$current_rev" != "$pinned_rev" ]; then
                    echo "syncing odysseus checkout ''${current_rev:-<empty>} → $pinned_rev"
                    git -C "$target" fetch --depth 1 origin "$pinned_rev"
                    git -C "$target" checkout --detach "$pinned_rev"
                    # requirements.txt may have changed between revs — force a
                    # re-check by invalidating the install marker.
                    rm -f "$target/.venv/.requirements.installed"
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
              ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
                export LD_LIBRARY_PATH="${wheelLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              ''}

              VENV_DIR="''${VENV_DIR:-$PWD/.venv}"
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

              exec uvicorn app:app --reload --host 0.0.0.0 --port "''${APP_PORT:-7000}"
            '';
          };
        in
        {
          devShells.default = pkgs.mkShell {
            name = "odysseus-dev";

            packages = allDeps;

            shellHook = ''
              # Capture where `nix develop` was invoked from BEFORE we cd
              # elsewhere — this is (most likely) the user's odysseus-nix
              # checkout, which the fmt/lint/build recipes need to be able
              # to write to.
              ODYSSEUS_NIX_DIR="''${ODYSSEUS_NIX_DIR:-$PWD}"

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
              ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
                export LD_LIBRARY_PATH="${wheelLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              ''}

              # One venv per project, kept out of the source tree.
              VENV_DIR="''${VENV_DIR:-$PWD/.venv}"
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
                  pip install -r "$REQS" && touch "$REQS_MARKER"
                fi

                REQS_OPT="$PWD/requirements-optional.txt"
                REQS_OPT_MARKER="$VENV_DIR/.requirements-optional.installed"
                if [ "''${ODYSSEUS_INSTALL_OPTIONAL:-0}" = "1" ] && [ -f "$REQS_OPT" ] \
                  && { [ ! -f "$REQS_OPT_MARKER" ] || [ "$REQS_OPT" -nt "$REQS_OPT_MARKER" ]; }; then
                  echo "installing optional python deps (requirements-optional.txt changed)…"
                  pip install -r "$REQS_OPT" && touch "$REQS_OPT_MARKER"
                fi

                PKG="$PWD/package.json"
                LOCK="$PWD/package-lock.json"
                NODE_MARKER="$PWD/node_modules/.installed"
                if [ -f "$PKG" ] && { [ ! -d "$PWD/node_modules" ] || [ ! -f "$NODE_MARKER" ] \
                  || [ "$PKG" -nt "$NODE_MARKER" ] \
                  || { [ -f "$LOCK" ] && [ "$LOCK" -nt "$NODE_MARKER" ]; }; }; then
                  echo "installing node deps (package.json/lock changed)…"
                  npm install && touch "$NODE_MARKER"
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

          # Packages — used by home-manager / `nix profile install` consumers.
          #   packages.default     — alias for odysseus-env
          #   packages.odysseus-env — buildEnv with all the tooling
          #   packages.odysseus-dev — the launcher script (also exposed as apps.default)
          packages = {
            default = odysseusEnv;
            odysseus-env = odysseusEnv;
            odysseus-dev = odysseusDev;
          };

          # `nix run github:KangaZero/odysseus-nix [-- /path/to/checkout]`
          apps.default = {
            type = "app";
            program = "${odysseusDev}/bin/odysseus-dev";
          };

          # `nix fmt` runs treefmt across the whole tree (nix/shell/md/yaml).
          formatter = treefmtEval.config.build.wrapper;

          # `nix flake check` (and `just check`) enforce formatting in CI.
          checks.formatting = treefmtEval.config.build.check self;
        });
}
