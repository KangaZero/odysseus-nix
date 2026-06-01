# Common odysseus dev tasks. Run `just` for the list.
#
# Recipes operate on the odysseus checkout pointed to by $ODYSSEUS_DIR
# (default: ../odysseus relative to this flake folder). The nix devShell
# sets this automatically.

set shell := ["bash", "-cu"]
set dotenv-load := true

odysseus_dir := env_var_or_default("ODYSSEUS_DIR", justfile_directory() + "/../odysseus")
port := env_var_or_default("APP_PORT", "7000")

default:
    @just --list

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

# Run the test suite.
test *args:
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

# Format this flake.
fmt:
    nix fmt

# Update flake.lock to the latest nixpkgs/flake-utils.
lock-update:
    nix flake update

# Validate the flake.
check:
    nix flake check

# Print resolved paths and versions.
info:
    @echo "odysseus_dir: {{odysseus_dir}}"
    @echo "port:         {{port}}"
    @echo "python:       $(python --version 2>&1)"
    @echo "node:         $(node --version 2>&1)"
    @echo "just:         $(just --version)"
