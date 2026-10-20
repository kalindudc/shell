# Development

## Setup

```bash
git clone https://github.com/kalindudc/shell.git
cd shell

# Install BATS, ShellCheck, shfmt and the Ruby and npm dev dependencies
task up
```

## Tasks

```bash
task --list
```

| Task | Description |
|------|-------------|
| `task install` | Install everything: packages, tools, setup, generated configs, stow, bb and cortex |
| `task install:packages` | Install the `packages.yml` lists for this platform, plus npm, pi and pipx packages |
| `task install:tools` | Install tools no package manager provides |
| `task install:setup` | Set up docker, the GPG signing key, herdr plugins, pi extension dependencies and the default shell |
| `task install:bb` | Start bb if needed and apply `bb.yml` |
| `task install:cortex` | Install cortex and its agent integrations |
| `task generate` | Write `home/.zshrc`, `home/.gitconfig` and the ghostty font-size config |
| `task generate:zsh`, `generate:git`, `generate:ghostty` | Write one of them |
| `task stow` | Link `home/` into `$HOME` |
| `task up` | Install development dependencies |
| `task test` | Run default local tests (unit + bin) |
| `task test:unit` | Run the Ruby installer tests, and the pi extension tests when bun is available |
| `task test:bin` | Run the `home/bin/` tool tests |
| `task test:integration` | Run integration tests separately (requires Docker and `task build`) |
| `task build` | Build Docker images for the integration tests |
| `task clean` | Clean integration containers and temp logs |
| `task style` | Run ShellCheck and RuboCop |

## Testing

### Unit Tests

```bash
task test:unit
```

Ruby installer tests use Minitest in `test/unit/`. Bin tests use BATS and Ruby under `home/bin/test/`.

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
./install.sh --trace packages   # print each command of one step
```

## Adding Packages

Edit `packages.yml`:

```yaml
apt:
  - new-package
```

`packages.yml` holds only package lists. A tool that no package manager provides gets an installer method in `src/install/tools.rb`, listed in `Tools::ALL`. Machine-specific bb state goes under `profiles:` in `bb.yml`, selected by `SHELL_MACHINE_PROFILE`.

## Code Standards

- Use `set -euo pipefail`
- Quote variables: `"$var"`
- Use `[[ ]]` for tests
- Pass ShellCheck: `task style`
