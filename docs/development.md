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
| `task clean` | Clean integration containers/images and temp logs |
| `task style` | Run ShellCheck and RuboCop |
| `task test` | Run default local tests (unit + bin) |
| `task test:unit` | Run Ruby installer tests and pi extension tests when bun is available |
| `task test:integration` | Run integration tests separately (requires Docker and `task build`) |
| `task build` | Build Docker images |
| `task generate` | Generate configs |

## Testing

### Unit Tests

```bash
task test:unit
```

Ruby installer tests use Minitest in `test/unit/test_installer.rb`. Bin tests use BATS and Ruby under `home/bin/test/`.

### Integration Tests

```bash
task build                    # First time
task test:integration         # All platforms
task test:integration -- ubuntu-22  # Single platform
```

Platforms: `ubuntu-22`, `ubuntu-24`, `debian`, `arch`, `ubuntu-minimal`. The minimal Ubuntu image starts without Ruby or Bundler so `install.sh` bootstrap assumptions stay covered.

## Debugging

```bash
TRACE=1 ./install.sh 2>&1 | tee install.log
cat "${XDG_STATE_HOME:-$HOME/.local/state}/shell/install.json"   # Reboot continuation state
```

## Adding Packages

Edit `packages.yml`:

```yaml
apt:
  - new-package

custom_bootstrap:
  - install_runtime_before_npm

machine_profiles:
  default:
    bootstrap:
      apt:
        - curl
```

Use `package_managers` for required package-manager bootstrap and `machine_profiles` for host/profile-specific prerequisites. Profile selection order is `SHELL_MACHINE_PROFILE`, hostname, then `default`.

## Code Standards

- Use `set -euo pipefail`
- Quote variables: `"$var"`
- Use `[[ ]]` for tests
- Pass ShellCheck: `task style`
