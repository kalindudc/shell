# The user's home on every machine: packages, dotfiles, zsh, git and ghostty.
{ lib, user, ... }:
{
  imports = [
    ./dotfiles.nix
    ./ghostty.nix
    ./git.nix
    ./packages.nix
    ./zsh.nix
  ];

  home.username = user.username;
  home.stateVersion = "26.11";
  manual.manpages.enable = false;

  # gpg refuses a home directory that other users can read.
  home.activation.gnupgPermissions = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run mkdir -p "$HOME/.gnupg"
    run chmod 700 "$HOME/.gnupg"
  '';
}
