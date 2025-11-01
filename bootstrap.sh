#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Simple logfile for first-boot debugging
log="$HOME/bootstrap.log"
exec > >(tee -a "$log") 2>&1
echo "== $(date -Iseconds) :: bootstrap start =="

# Helper to persist lines once
append_if_missing() {
  local line="$1" file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

###############################################################################
# System deps (one update, then installs)
###############################################################################
sudo apt-get update
sudo apt-get install -y \
  build-essential curl git ca-certificates gnupg xclip \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

###############################################################################
# R + user-packages
###############################################################################
if ! command -v R >/dev/null 2>&1; then
  sudo apt-get install -y r-base r-base-dev
  # If you compile R pkgs often, consider uncommenting these:
  # sudo apt-get install -y libcurl4-openssl-dev libssl-dev libxml2-dev
fi

if command -v R >/dev/null 2>&1; then
  Rscript - <<'RS'
options(repos = c(CRAN = "https://cloud.r-project.org"))
dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE, showWarnings = FALSE)
pkgs <- c("languageserver","dplyr","data.table","optparse","jsonlite","clipr","bit64","httpgd")
need <- setdiff(pkgs, rownames(installed.packages()))
if (length(need)) {
  install.packages(need, lib = Sys.getenv("R_LIBS_USER"),
                   Ncpus = max(1, parallel::detectCores() - 1))
}
RS
fi

# VS Code (code-server) R extension (no-op if code-server absent)
if command -v code-server >/dev/null 2>&1; then
  code-server --install-extension REditorSupport.r --force >/dev/null 2>&1 || true
fi

###############################################################################
# pyenv + Python 3.12.x + Poetry 1.8.x
###############################################################################
PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12.12}"
POETRY_VERSION="${POETRY_VERSION:-1.8.5}"

# Install pyenv once
if [ ! -d "$PYENV_ROOT" ]; then
  curl -fsSL https://pyenv.run | bash
fi

# Make pyenv available now and in future shells
export PYENV_ROOT="$PYENV_ROOT"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init -)"
else
  echo "pyenv not on PATH; check install steps above." >&2
fi

append_if_missing 'export PYENV_ROOT="$HOME/.pyenv"' "$HOME/.bashrc"
append_if_missing 'export PYENV_ROOT="$HOME/.pyenv"' "$HOME/.zshrc"
append_if_missing 'export PATH="$PYENV_ROOT/bin:$PATH"' "$HOME/.bashrc"
append_if_missing 'export PATH="$PYENV_ROOT/bin:$PATH"' "$HOME/.zshrc"
append_if_missing 'eval "$(pyenv init -)"' "$HOME/.bashrc"
append_if_missing 'eval "$(pyenv init -)"' "$HOME/.zshrc"

# Install desired Python (no-op if present) and select it
if command -v pyenv >/dev/null 2>&1; then
  pyenv install -s "$PYTHON_VERSION"
  pyenv global "$PYTHON_VERSION"
fi
PYENV_PY="$PYENV_ROOT/versions/$PYTHON_VERSION/bin/python"

# Poetry via official installer; ensure ~/.local/bin on PATH now and later
if ! command -v poetry >/dev/null 2>&1 || ! poetry --version | grep -q "$POETRY_VERSION"; then
  curl -sSL https://install.python-poetry.org | python3 - --version "$POETRY_VERSION"
fi
export PATH="$HOME/.local/bin:$PATH"
append_if_missing 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"
append_if_missing 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc"

# Per-project .venv setup (skip if repo dir missing)
for P in "/workspace/ethan-kochav-scratch" "/workspace/ethan-kochav-catbond-email-parser"; do
  [ -d "$P" ] || { echo "Skipping $P (missing)"; continue; }
  if [ -f "$P/pyproject.toml" ]; then
    (
      cd "$P"
      poetry config virtualenvs.in-project true --local
      [ -x "$PYENV_PY" ] && poetry env use "$PYENV_PY" || true
      poetry install --no-interaction --no-root || true
    )
  else
    echo "Skipping $P (no pyproject.toml)"
  fi
done

###############################################################################
# Node.js LTS (optional) + npm global tools (non-fatal if they fail)
###############################################################################
# NodeSource LTS
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - || true
sudo apt-get install -y nodejs || true
sudo npm install -g npm@latest || true

# Copilot CLI: package names change occasionally; tolerate failure
# Option A: npm package (may be named 'github-copilot-cli' depending on version)
sudo npm install -g github-copilot-cli || true
# Option B: gh extension (requires GitHub CLI)
# gh extension install github/gh-copilot || true

echo "-- Versions:"
echo "R:        $(R --version 2>/dev/null | head -n1 || echo 'not installed')"
echo "Python:   $(python3 --version 2>/dev/null || echo 'n/a')"
echo "pyenv:    $(pyenv --version 2>/dev/null || echo 'n/a')"
echo "Poetry:   $(poetry --version 2>/dev/null || echo 'n/a')"
echo "Node:     $(node --version 2>/dev/null || echo 'n/a')"
echo "npm:      $(npm --version 2>/dev/null || echo 'n/a')"

echo "== $(date -Iseconds) :: bootstrap done =="
exit 0
