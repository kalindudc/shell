# Builds ~/.zshrc from nix/home/zsh/zshrc.zsh and the fragments it includes. Edit those
# files, then run `task switch`.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  profiles = [
    config.home.profileDirectory
  ]
  ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin "/run/current-system/sw"
  ++ [ "/nix/var/nix/profiles/default" ];

  # The layout the old git clones in ~/.local/share/zsh/plugins had.
  zshPlugins = pkgs.linkFarm "zsh-plugins" [
    {
      name = "evalcache";
      path = inputs.evalcache;
    }
    {
      name = "fast-syntax-highlighting";
      path = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting";
    }
    {
      name = "ohmyzsh";
      path = "${pkgs.oh-my-zsh}/share/oh-my-zsh";
    }
    {
      name = "zsh-autosuggestions";
      path = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions";
    }
    {
      name = "zsh-completions/src";
      path = "${pkgs.zsh-completions}/share/zsh/site-functions";
    }
  ];

  fragments = map (name: "${name}.zsh") [
    "base"
    "zsh-config"
    "aliases"
    "git"
    "functions"
    "kubernetes"
    "agents"
    "misc"
  ];

  zshrc =
    builtins.replaceStrings
      (
        [
          "@nixPath@"
          "@nixSiteFunctions@"
          "@zshPlugins@"
        ]
        ++ map (file: "# @include ${file}") fragments
      )
      (
        [
          (lib.concatMapStringsSep ":" (profile: "${profile}/bin") profiles)
          (lib.concatMapStringsSep " " (profile: "${profile}/share/zsh/site-functions") profiles)
          "${zshPlugins}"
        ]
        ++ map (file: builtins.readFile ./zsh/${file}) fragments
      )
      (builtins.readFile ./zsh/zshrc.zsh);
in
{
  home.file.".zshrc".text = ''
    # Generated from nix/home/zsh in the shell repo. Edit those files, then run `task switch`.

    # Variables Home Manager sets (home.sessionVariables)
    [[ -f ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh ]] && \
      source ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh

    ${zshrc}
  '';

  # Cached init scripts (evalcache) and the completion dump name store paths that a switch
  # replaces, and ~/.zshrc is a store link whose time never changes, so clear them here.
  home.activation.clearZshCaches = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run rm -rf "$HOME/.zsh-evalcache"
    run rm -f "$HOME"/.zcompdump*
  '';
}
