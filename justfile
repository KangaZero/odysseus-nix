# Common odysseus-nix dev tasks. Run `just` for the list.
#
# App recipes (run, dev, pytest, docker-*, install-*) operate on the
# odysseus checkout pointed to by $ODYSSEUS_DIR (default: ../odysseus
# relative to this flake folder). The nix devShell sets this automatically.
#
# Flake/CI recipes (test, fmt, fmt-check, lint, check, build) operate on
# this flake folder itself and are what CI / git pre-push enforce.

set shell := ["bash", "-cu"]
set dotenv-load := true

odysseus_dir := env_var_or_default("ODYSSEUS_DIR", justfile_directory() + "/../odysseus")
port := env_var_or_default("APP_PORT", "7000")
flake_dir := justfile_directory()

default:
    @just --list

# ─── CI gate ──────────────────────────────────────────────────────────────
# The one command CI runs and the git pre-push hook enforces. Any failure
# here blocks a push. Keep it fast — pure-Nix checks, no network beyond the
# flake inputs already in the lock file.

# Run every check the CI / pre-push hook enforces.
test: fmt-check lint check build
    @echo ""
    @echo "✅ all checks passed"

# Verify the tree is formatted (no writes). Run `just fmt` to fix.
fmt-check:
    @echo "→ treefmt --ci (nix/shell/md/yaml)"
    cd "{{flake_dir}}" && nix fmt -- --ci

# Lint nix files: statix (anti-patterns) + deadnix (dead bindings) +
# shellcheck (hooks).
lint:
    @echo "→ statix check"
    cd "{{flake_dir}}" && statix check .
    @echo "→ deadnix --fail"
    cd "{{flake_dir}}" && deadnix --fail .
    @echo "→ shellcheck .githooks/pre-push"
    cd "{{flake_dir}}" && shellcheck .githooks/pre-push

# Validate the flake. Two passes: (1) native `nix flake check` builds and runs
# this platform's checks (incl. the treefmt `formatting` check) + packages;
# (2) `--all-systems --no-build` evaluates every system's outputs to catch eval
# errors WITHOUT trying to build foreign-platform derivations (which fails on a
# CI runner that can't cross-build — e.g. an x86_64 box building an aarch64
# check). The build pass is intentionally native-only.
check:
    @echo "→ nix flake check (native: build + run checks)"
    cd "{{flake_dir}}" && nix flake check
    @echo "→ nix flake check --all-systems --no-build (eval every system)"
    cd "{{flake_dir}}" && nix flake check --all-systems --no-build

# Build every exposed package for the current system.
build:
    @echo "→ nix build .#default .#odysseus-dev"
    cd "{{flake_dir}}" && nix build .#default .#odysseus-dev --no-link --print-out-paths

# Format the whole tree in-place (nix/shell/md/yaml) via treefmt.
fmt:
    cd "{{flake_dir}}" && nix fmt

# Update flake.lock to the latest nixpkgs/flake-utils.
lock-update:
    nix flake update

# Install the git pre-push hook so `just test` runs before every push.
install-hooks:
    git config core.hooksPath .githooks
    @echo "✅ git pre-push hook active (runs `just test`)"
    @echo "   uninstall: git config --unset core.hooksPath"

# ─── Odysseus app recipes ─────────────────────────────────────────────────

# Install core Python deps into the active venv.
install:
    cd "{{odysseus_dir}}" && pip install -r requirements.txt

# Install optional deps (DuckDuckGo search, PyMuPDF form-filling).
install-optional:
    cd "{{odysseus_dir}}" && pip install -r requirements-optional.txt

# Install npm deps (Anthropic SDK + Antithesis Bombadil).
install-node:
    cd "{{odysseus_dir}}" && npm install

# Install everything: core Python + npm.
install-all: install install-node

# Run the FastAPI app with auto-reload.
run:
    cd "{{odysseus_dir}}" && uvicorn app:app --reload --host 0.0.0.0 --port {{port}}

# Alias for `run`.
dev: run

# Run the odysseus pytest suite.
pytest *args:
    cd "{{odysseus_dir}}" && pytest {{args}}

# Build and start the docker-compose stack.
docker-up:
    cd "{{odysseus_dir}}" && docker compose up --build -d

# Stop the docker-compose stack.
docker-down:
    cd "{{odysseus_dir}}" && docker compose down

# Tail docker-compose logs.
docker-logs:
    cd "{{odysseus_dir}}" && docker compose logs -f

# Remove the venv, node_modules, and auto-install markers from the odysseus
# checkout. The mtime markers (.requirements.installed etc.) live inside
# .venv / node_modules, so deleting those dirs forces a clean re-install on
# the next `nix develop` / `just install`.
clean:
    cd "{{odysseus_dir}}" && rm -rf .venv node_modules
    @echo "✅ removed .venv and node_modules from {{odysseus_dir}}"

# Print resolved paths and versions.
info:
    @echo "odysseus_dir: {{odysseus_dir}}"
    @echo "port:         {{port}}"
    @echo "python:       $(python --version 2>&1)"
    @echo "node:         $(node --version 2>&1)"
    @echo "just:         $(just --version)"

# ─── Optional services ────────────────────────────────────────────────────
# These require additional setup — see README for details.

# Start a local ChromaDB vector-store server on localhost:8100 (no Docker).
# Requires the full chromadb package: pip uninstall chromadb-client && pip install chromadb
# Data is stored in {{odysseus_dir}}/data/chromadb (created on first run).
chromadb:
    chroma run --host localhost --port 8100 --path "{{odysseus_dir}}/data/chromadb"

# Seed the npx cache with @playwright/mcp so Odysseus can launch the Playwright MCP server.
# Run once after `nix develop`; browsers are managed by Nix (no extra download needed).
playwright-mcp:
    npx -y @playwright/mcp@latest --version
