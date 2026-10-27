# Standalone Home Manager on Arch, Ubuntu or Debian. The distribution keeps zsh, Docker and
# the desktop apps (src/scripts/linux-system.sh).
{ pkgs, user, ... }:
{
  home.homeDirectory = "/home/${user.username}";

  # Puts the home-manager command on PATH after the first switch.
  programs.home-manager.enable = true;

  targets.genericLinux.enable = true;
  # No graphical app comes from Nix, so the host's GPU drivers need no setup.
  targets.genericLinux.gpu.enable = false;

  fonts.fontconfig.enable = true;
  home.packages = with pkgs.nerd-fonts; [
    caskaydia-mono
    fira-code
    hack
    jetbrains-mono
    meslo-lg
    sauce-code-pro
    symbols-only
  ];
}
