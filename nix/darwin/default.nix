# macOS system settings for the personal and work Macs. The work profile differs only in
# the packages that Tec supplies (nix/home/packages.nix and nix/home/git.nix).
{
  inputs,
  lib,
  pkgs,
  profile,
  user,
  ...
}:
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfreePredicate = import ../unfree.nix { inherit lib; };

  # Determinate Nix (personal) or Tec (work) owns the Nix daemon and /etc/nix.
  nix.enable = false;

  # Keep the /etc/zshrc and /etc/bashrc that the Nix installer wrote. ~/.zshrc puts the
  # Nix profiles on PATH itself, so nix-darwin does not need to replace those files.
  programs.zsh.enable = false;
  programs.bash.enable = false;

  # macOS, Tec or the MDM may already own /etc/ssl/certs/ca-certificates.crt, and nix-darwin
  # stops the first activation when a file it manages exists with other contents.
  security.pki.installCACerts = false;

  # Manual generation needs the nixpkgs source and fails without it.
  documentation.enable = false;

  # `task switch` applies the same profile again (src/scripts/switch.sh).
  environment.etc."shell-profile".text = profile;

  system.primaryUser = user.username;
  system.stateVersion = 6;
  users.users.${user.username}.home = "/Users/${user.username}";

  security.pam.services.sudo_local.touchIdAuth = true;

  # Ghostty uses JetBrainsMono and CaskaydiaMono; the rest match the Linux font list.
  fonts.packages = with pkgs.nerd-fonts; [
    caskaydia-mono
    fira-code
    hack
    jetbrains-mono
    meslo-lg
    sauce-code-pro
    symbols-only
  ];

  # install.sh installs Homebrew itself. Apps installed by other means are left alone.
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };
    casks = [
      "bb"
      "discord"
      "docker-desktop"
      "ghostty"
      "google-chrome"
      "visual-studio-code"
    ];
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "before-nix";
    extraSpecialArgs = { inherit inputs user profile; };
    users.${user.username}.imports = [ ../home ];
  };
}
