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
task test:integration   # Integration tests (requires Docker)
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

1. Update `src/install/os.rb` - detection and backend mapping
2. Update `packages.yml` - package-manager, machine-profile, and backend declarations
3. Add `test/integration/dockerfiles/Dockerfile.{platform}` and compose service wiring
4. Test: `task build && task test:integration -- platform`
