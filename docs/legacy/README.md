# Legacy Scripts

The OS-specific scripts here are deprecated. Use the unified `install.sh` instead.

## Old → New

```bash
# Old (deprecated)
./install-macos.sh
./install-linux.sh
./install-arch.sh

# New
./install.sh
```

The new installer auto-detects your OS and provides:
- State tracking (resume on failure)
- Category-based installation
- Lock file protection
