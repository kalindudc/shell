# Troubleshooting

## Installation Fails

```bash
# Remove stale locks
rm -f ./tmp/shell_install.lock ~/.shell_install.lock

# View state
./install.sh --show-state

# Continue or reset
./install.sh --continue
./install.sh --reset-state

# Debug
TRACE=1 ./install.sh 2>&1 | tee install.log
```

## Package Fails

```bash
# Update package manager first
brew update          # macOS
sudo apt-get update  # Ubuntu
sudo pacman -Syu     # Arch

# Try manually
brew install package-name
sudo apt-get install package-name
sudo pacman -S package-name
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

## State Issues

```bash
# View state
cat ~/.shell_install_state

# Reset
./install.sh --reset-state
rm -f ~/.shell_install_state
```

## Platform-Specific

### macOS: Homebrew Not Found

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"  # Apple Silicon
eval "$(/usr/local/bin/brew shellenv)"     # Intel
```

### Ubuntu: GPG Errors

```bash
sudo apt-get install gnupg
./install.sh --continue
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

## Complete Uninstall

```bash
# Remove stowed files
stow -D -v -d . -t ~ home

# Remove configs
rm -rf ~/.oh-my-zsh ~/.config/starship.toml

# Reset shell
chsh -s /bin/bash

# Remove repo
rm -rf ~/src/github.com/kalindudc/shell
```
