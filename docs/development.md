# Development

## Setup

```bash
git clone --recurse-submodules https://github.com/kalindudc/shell.git
cd shell

nix develop   # bats, go-task, nixfmt, ruby, shellcheck and shfmt
task up       # Ruby gems, npm packages and the pre-commit hook
```

## Tasks

```bash
task --list
```

| Task | Description |
|------|-------------|
| `task install` | Set up the machine (`./install.sh`) |
| `task switch` | Apply the flake |
| `task update` | Update `flake.lock` |
| `task check` | Evaluate every configuration and build this system's checks |
| `task tools`, `task setup`, `task bb`, `task cortex` | Run one step of `src/install.rb` |
| `task clean` | Remove test logs |
| `task style` | Run ShellCheck, shfmt, RuboCop and `nix fmt` |
| `task test` | Run the local tests (unit + bin) |
| `task test:unit` | Run the Ruby installer tests, and the pi extension tests when bun is available |

## Testing

```bash
task test:unit   # Ruby installer tests (Minitest) in test/unit/
task test:bin    # home/bin tests (BATS and Ruby) in home/bin/test/
task check       # nix flake check
```

Before a switch, build the configuration without applying it:

```bash
nix build .#darwinConfigurations.personal.system                  # macOS
nix build .#homeConfigurations.linux-x86_64.activationPackage     # Linux
```

`result/home-files` (Linux) shows every file Home Manager would write. CI runs
`nix flake check` on macOS and Ubuntu, and applies the Linux configuration for a test user
on Ubuntu (`.github/workflows/check.yml`). A weekly workflow opens a pull request that
updates `flake.lock`.

## Debugging

```bash
TRACE=1 ./install.sh 2>&1 | tee install.log
nix eval .#darwinConfigurations.personal.config.homebrew.casks          # read any option
nix eval --raw .#homeConfigurations.linux-x86_64.config.home.file.".zshrc".text
```

## Adding Packages

See "Adding Packages" in [installation.md](installation.md).

## Code Standards

- Use `set -euo pipefail`
- Quote variables: `"$var"`
- Use `[[ ]]` for tests
- Pass ShellCheck: `task style`
- Format Nix with `nix fmt`
