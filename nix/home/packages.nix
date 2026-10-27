# Command-line tools for every machine. Agent CLIs (pi, pnpm) come from npm and dunk from
# pipx (packages.yml), because nixpkgs lags behind them.
{
  lib,
  pkgs,
  profile,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  # Tec supplies these on the work Mac, ahead of the Nix profile on PATH.
  tecTools = with pkgs; [
    gh
    ruby
  ];

  todoCompletion = pkgs.runCommand "todo-zsh-completion" { nativeBuildInputs = [ pkgs.ruby ]; } ''
    mkdir -p $out/share/zsh/site-functions
    ruby ${../../home/bin}/todo --completions zsh > $out/share/zsh/site-functions/_todo
  '';
in
{
  home.packages =
    with pkgs;
    [
      atuin
      delta
      direnv
      fd
      fnm
      fzf
      gnupg
      go
      go-task
      gum
      herdr
      jq
      kubecolor
      kubectl
      kubernetes-helm
      lazygit
      neovim
      pipx
      pyenv
      ripgrep
      starship
      stern
      wget
      zoxide
      todoCompletion
    ]
    ++ lib.optionals (profile != "work") tecTools
    ++ lib.optionals isDarwin [
      _1password-cli
      # gdate, for the shell start-up timer
      coreutils-prefixed
    ]
    ++ lib.optionals isLinux [
      bc
      xclip
    ];
}
