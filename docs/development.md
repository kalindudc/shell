# Development

## Setup

```bash
git clone https://github.com/kalindudc/shell.git
cd shell

# Install BATS and ShellCheck (or use task dev:deps)
# On macOS: brew install bats-core shellcheck
# On Arch:  pacman -S bats shellcheck
# On Ubuntu: apt install bats shellcheck
```

## Tasks

```bash
task --list
```

| Task | Description |
|------|-------------|
| `task install` | Run installation |
| `task stow` | Re-stow dotfiles |
| `task clean` | Clean state and temp files |
| `task style` | Run ShellCheck |
| `task test` | Run all tests |
| `task test:unit` | Run unit tests |
| `task test:integration` | Run integration tests (requires Docker) |
| `task build` | Build Docker images |
| `task generate` | Generate configs |

## Testing

### Unit Tests

```bash
task test:unit
```

Tests use BATS. Add tests in `test/unit/`.

### Integration Tests

```bash
task build                    # First time
task test:integration         # All platforms
task test:integration -- ubuntu-22  # Single platform
```

Platforms: `ubuntu-22`, `ubuntu-24`, `debian`, `arch`

## Debugging

```bash
TRACE=1 ./install.sh         # Debug output
./install.sh --show-state    # View state
cat ~/.shell_install_state   # Raw state file
```

## Adding Packages

Edit `src/lib/packages.sh`:

```bash
# Add to appropriate PACKAGES_* array
readonly PACKAGES_DEV=(
  "neovim"
  "gh"
  "new-package"
)
```

## Code Standards

- Use `set -euo pipefail`
- Quote variables: `"$var"`
- Use `[[ ]]` for tests
- Pass ShellCheck: `task style`
