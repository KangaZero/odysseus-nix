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
    ] (system:
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
        linuxDeps = with pkgs; pkgs.lib.optionals stdenv.isLinux [
          gosu
          glibcLocales
        ];

        # macOS: nothing extra required — the SDK frameworks are pulled in
        # automatically by stdenv on Darwin.
        darwinDeps = with pkgs; pkgs.lib.optionals stdenv.isDarwin [ ];
      in
      {
        devShells.default = pkgs.mkShell {
          name = "odysseus-dev";

          packages = commonDeps ++ linuxDeps ++ darwinDeps;

          shellHook = ''
            # Quality-of-life: drop into the sibling odysseus checkout if it
            # exists. Override with ODYSSEUS_DIR=/path/to/odysseus nix develop.
            export ODYSSEUS_DIR="''${ODYSSEUS_DIR:-$PWD/../odysseus}"

            if [ -d "$ODYSSEUS_DIR" ]; then
              cd "$ODYSSEUS_DIR"
            else
              echo "note: \$ODYSSEUS_DIR ($ODYSSEUS_DIR) not found — staying in $PWD"
            fi

            # One venv per project, kept out of the source tree.
            VENV_DIR="''${VENV_DIR:-$PWD/.venv}"
            if [ ! -d "$VENV_DIR" ]; then
              echo "creating venv at $VENV_DIR"
              ${python.interpreter} -m venv "$VENV_DIR"
            fi
            # shellcheck disable=SC1091
            source "$VENV_DIR/bin/activate"

            echo ""
            echo "odysseus dev shell ready (${system})"
            echo "  python:  $(python --version)"
            echo "  node:    $(node --version)"
            echo "  venv:    $VENV_DIR"
            echo ""
            echo "next:  pip install -r requirements.txt"
            echo "       uvicorn app:app --reload --port 7000"
          '';
        };

        # `nix fmt` formats this flake.
        formatter = pkgs.nixpkgs-fmt;
      });
}
