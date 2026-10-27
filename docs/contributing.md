# Contributing

## Getting Started

1. Fork the repository
2. Clone your fork
3. Create a feature branch

## Code Standards

- `set -euo pipefail` at script start
- Quote all variables: `"$var"`
- Use `[[ ]]` for tests
- Pass ShellCheck: `task style`

## Testing

```bash
task style              # Lint
task test:unit          # Unit tests
task check              # Nix configurations
```

## Commit Messages

```
type(scope): description

- Detailed explanation
- Reference issues: Fixes #123
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## Pull Request

1. Run tests: `task style && task test`
2. Push: `git push origin feature/my-feature`
3. Create PR with description and testing done

## Adding Platforms

1. Add a configuration to `flake.nix`: a `darwinConfigurations` entry for a Mac, or a
   `homeConfigurations` entry for another Linux architecture
2. For a Linux distribution, add its package manager to `src/scripts/linux-system.sh`
3. Test: `task check`, then `task switch` on the machine
