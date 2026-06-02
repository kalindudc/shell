#!/usr/bin/env bash

NPM_COMMAND="npm"
if command -v pnpm >/dev/null 2>&1; then
  NPM_COMMAND="pnpm"
fi

GEM_BIN=$(ruby -e 'puts Gem.user_dir + "/bin"')

# Install shell dev tools required for task test:unit and task style
if [[ "$OSTYPE" == "darwin"* ]]; then
  brew install bats-core shellcheck shfmt
elif [[ -f /etc/arch-release ]]; then
  sudo pacman -S --needed --noconfirm bats shellcheck shfmt
else
  sudo apt-get install -y bats shellcheck
  # shfmt not in apt on older Ubuntu; install via go if available
  if command -v go >/dev/null 2>&1; then
    go install mvdan.cc/sh/v3/cmd/shfmt@latest
  fi
fi

if [ $? -ne 0 ]; then
  echo "Error: Failed to install dev tools. Please check the output above for details."
  exit 1
fi

echo "✓ Dev tools installed"

REQUIRED_BUNDLER="4.0.3"
BUNDLE_BIN="$GEM_BIN/bundle"

# Install the required bundler version to the user gem dir if missing
if ! "${BUNDLE_BIN}" --version 2>/dev/null | grep -q "${REQUIRED_BUNDLER}"; then
  echo "Installing bundler ${REQUIRED_BUNDLER}..."
  gem install bundler -v "${REQUIRED_BUNDLER}" --user-install
fi

# Set global bundle config so all projects install gems to the user gem dir
# and never require root. This persists in ~/.bundle/config.
"${BUNDLE_BIN}" config set --global path "$(ruby -e 'puts Gem.user_dir')"
"${BUNDLE_BIN}" config set --global bin "$GEM_BIN"

"${BUNDLE_BIN}" install

# fail if bundle install fails, otherwise we might have a broken setup and the user won't know until they try to run a task
if [ $? -ne 0 ]; then
  echo "Error: bundle install failed. Please check the output above for details."
  exit 1
fi

echo "Setup NPM"
$NPM_COMMAND install

echo "✓ Development dependencies installed"
