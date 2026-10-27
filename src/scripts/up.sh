#!/usr/bin/env bash

# Development dependencies for `task test` and `task style`. bats, shellcheck, shfmt and
# nixfmt come from the flake's dev shell: run `nix develop` first.

set -euo pipefail

NPM_COMMAND="npm"
if command -v pnpm >/dev/null 2>&1; then
  NPM_COMMAND="pnpm"
fi

GEM_BIN="$(ruby -e 'puts Gem.user_dir + "/bin"')"
REQUIRED_BUNDLER="4.0.3"
BUNDLE_BIN="${GEM_BIN}/bundle"

# Install the required bundler version to the user gem dir if missing
if ! "${BUNDLE_BIN}" --version 2>/dev/null | grep -q "${REQUIRED_BUNDLER}"; then
  echo "Installing bundler ${REQUIRED_BUNDLER}..."
  gem install bundler -v "${REQUIRED_BUNDLER}" --user-install
fi

# Set global bundle config so all projects install gems to the user gem dir
# and never require root. This persists in ~/.bundle/config.
"${BUNDLE_BIN}" config set --global path "$(ruby -e 'puts Gem.user_dir')"
"${BUNDLE_BIN}" config set --global bin "${GEM_BIN}"
"${BUNDLE_BIN}" install

echo "Setup NPM"
"${NPM_COMMAND}" install

# The pre-commit hook blocks commits that would publish private details from the bb automation backup
git -C "$(dirname "$0")/../.." config core.hooksPath .githooks

echo "✓ Development dependencies installed"
