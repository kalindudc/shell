# Troubleshooting

## Installation Fails

```bash
# Debug
TRACE=1 ./install.sh 2>&1 | tee install.log

# Re-run after fixing the reported command or dependency
./install.sh
```

The installer has no lock file and no `--continue`, `--reset-state`, or `--show-state` flags. Required command failures stop the run with the failing command. Optional work is reported as a warning.

## Package Fails

```bash
# A Nix package: build the configuration to see the error
nix build .#darwinConfigurations.personal.system                # macOS
nix build .#homeConfigurations.linux-x86_64.activationPackage   # Linux

# A Homebrew cask that nix-darwin installs
brew install --cask package-name

# A Linux system package from src/scripts/linux-system.sh
sudo apt-get install package-name
sudo pacman -S package-name
```

## Undo a Switch

```bash
# macOS: activate the previous system generation
sudo darwin-rebuild --rollback

# Linux: list Home Manager generations, then run the activate script of an older one
home-manager generations
/nix/store/<hash>-home-manager-generation/activate
```

## Shell Not Zsh

```bash
# Check
echo $SHELL

# Set manually
chsh -s /usr/bin/zsh

# Or start manually
exec zsh
```

## Command Not Found

```bash
# Reload shell
source ~/.zshrc
exec zsh

# Check PATH
echo $PATH
which command-name
```

## A Login Is Needed

On Linux, joining the docker group and switching the login shell to zsh take effect after a
new login. `./install.sh` lists them at the end; log out and back in.

## Platform-Specific

### macOS: Homebrew Not Found

The Ruby installer bootstraps Homebrew when `brew` is missing. If Homebrew is installed but not on PATH, load it manually and rerun:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"  # Apple Silicon
eval "$(/usr/local/bin/brew shellenv)"     # Intel
```

### Ubuntu: GPG Errors

```bash
sudo apt-get install gnupg
./install.sh
```

### Arch: AUR Issues

```bash
# Install yay first
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay.git
cd yay && makepkg -si
```

## NVIDIA Drivers Break After Kernel Update

Symptoms: `nvidia-smi` fails, blank screen on boot, `lsmod | grep nvidia` empty.

```bash
# Diagnose
nvidia-diagnose

# Quick manual check — compare these two
uname -r
dpkg -l | grep linux-modules-nvidia | awk '{print $2, $3}'
```

The versioned module package for the running kernel is missing. Fix:

```bash
# Replace <branch> with your driver branch (e.g. 580) and <kernel> with uname -r output
sudo apt install linux-modules-nvidia-<branch>-open-<kernel>

# Install the meta-package so this never happens again on kernel updates
sudo apt install linux-modules-nvidia-<branch>-open-generic-hwe-24.04
```

See also: `nvidia-diagnose --help` for full check list, `nvidia-diagnose --sudo-setup` for
granting limited read access to privileged sysfs paths.

## Monitor Gets No Signal During GRUB / Plymouth / LUKS Prompt

Symptoms: main monitor (connected to RTX 3080) shows no signal until the login screen.
Happens ~50% of boots, always after a full shutdown. Disappears on warm reboot.

Cause: UEFI initialises its GOP framebuffer on the Intel iGPU by default on cold boot.
`simpledrm` (the early kernel framebuffer) inherits that iGPU output. The NVIDIA driver
only takes over at the display manager — 15-20 seconds into boot.

### Fix 1 — BIOS (recommended)

Board: MSI PRO Z690-A DDR4 (MS-7D25), BIOS 1.K0

1. Power on → press `Delete` at POST to enter BIOS
2. Press `F7` to switch to Advanced Mode if needed
3. Navigate: `SETTINGS` → `Advanced` → `Integrated Graphics Configuration`
4. Set `Initiate Graphic Adapter`: `Auto` → `PEG`
5. Press `F10` → Save & Exit

`PEG` forces the UEFI GOP framebuffer to initialise on the PCIe GPU (RTX 3080) from the
first pixel. GRUB, Plymouth, and the LUKS prompt will all appear on the main monitor.

Tip: if the submenu is hard to find, press `Ctrl+F` inside the BIOS and search `Graphic`.

The iGPU is NOT disabled by this change — Intel QuickSync and the rear IO display ports
remain fully functional in the OS.

### Fix 2 — GRUB (if BIOS fix alone is insufficient)

```bash
# /etc/default/grub
GRUB_GFXMODE=1920x1080,auto
GRUB_GFXPAYLOAD_LINUX=keep

sudo update-grub
```

This locks GRUB to the GOP output the BIOS handed it (now the RTX 3080) rather than
resetting the display mode at handover.

## Home Manager says a file "would be clobbered"

A file Home Manager wants to link already exists, and so does its `.before-nix` backup from an
earlier switch. Check both, delete the backup, then run `task switch` again.

## Old stow links

`task switch` removes links that point into `home/` from the old stow layout
(`src/scripts/unstow.sh`). It keeps the old `~/.gitconfig` as `~/.gitconfig.before-nix` and
moves only the lines tools added after the generated part into the new `~/.gitconfig`.

## Complete Uninstall

```bash
# macOS: remove nix-darwin and everything it installed (Home Manager links included)
sudo darwin-uninstaller

# Linux: remove Home Manager's links and packages
home-manager uninstall

# Reset the login shell (Linux)
chsh -s /bin/bash

# Then delete the checkout at ~/src/github.com/kalindudc/shell
```
