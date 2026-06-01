{
  description = "Odysseus dev shell — Python 3.12 + Node + system deps for local development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ]
      (system:
        let
          pkgs = import nixpkgs { inherit system; };

          python = pkgs.python312;

          # System-level deps mirroring the Dockerfile so `pip install -r
          # requirements.txt` can build native wheels (numpy, cryptography,
          # bcrypt, PyMuPDF, fastembed/onnxruntime, etc.) on any supported arch.
          commonDeps = with pkgs; [
            python
            python.pkgs.pip
            python.pkgs.virtualenv

            nodejs_26
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
          darwinDeps = pkgs.lib.optionals pkgs.stdenv.isDarwin [ ];

          allDeps = commonDeps ++ linuxDeps ++ darwinDeps;

          # Aggregated environment so home-manager / `nix profile install`
          # users can pull in all the tooling with a single package.
          odysseusEnv = pkgs.buildEnv {
            name = "odysseus-env";
            paths = allDeps;
          };

          # Standalone launcher for `nix run`. Bootstraps a venv on a checkout
          # (path arg, $ODYSSEUS_DIR, or $PWD), installs requirements.txt, and
          # exec's uvicorn. Used by apps.default below.
          odysseusDev = pkgs.writeShellApplication {
            name = "odysseus-dev";
            runtimeInputs = allDeps;
            # Pip drives its own subprocesses; let the shellcheck through.
            checkPhase = "";
            text = ''
              target="''${1:-''${ODYSSEUS_DIR:-$PWD}}"
              if [ ! -f "$target/app.py" ] || [ ! -f "$target/requirements.txt" ]; then
                echo "error: $target does not look like an odysseus checkout" >&2
                echo "       (expected app.py and requirements.txt)" >&2
                echo "" >&2
                echo "usage:" >&2
                echo "  nix run github:KangaZero/odysseus-nix -- /path/to/odysseus" >&2
                echo "  ODYSSEUS_DIR=/path/to/odysseus nix run github:KangaZero/odysseus-nix" >&2
                echo "" >&2
                echo "or clone first:" >&2
                echo "  git clone https://github.com/pewdiepie-archdaemon/odysseus.git" >&2
                echo "  cd odysseus && nix run github:KangaZero/odysseus-nix" >&2
                exit 1
              fi

              cd "$target"
              mkdir -p data logs services/cache/search

              VENV_DIR="''${VENV_DIR:-$PWD/.venv}"
              if [ ! -d "$VENV_DIR" ]; then
                echo "creating venv at $VENV_DIR"
                ${python.interpreter} -m venv "$VENV_DIR"
              fi
              # shellcheck disable=SC1091
              source "$VENV_DIR/bin/activate"

              MARKER="$VENV_DIR/.requirements.installed"
              if [ ! -f "$MARKER" ] || [ requirements.txt -nt "$MARKER" ]; then
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

          # `nix fmt` formats this flake.
          formatter = pkgs.nixpkgs-fmt;
        });
}
