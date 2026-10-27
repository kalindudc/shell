# Home Manager writes this to ~/.config/git/config, which is read-only. Git reads
# ~/.gitconfig after it, so that file stays writable for tools such as dev, gh and
# `git maintenance`.
{
  lib,
  pkgs,
  profile,
  user,
  ...
}:
{
  home.activation.writableGitConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [[ ! -e "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" ]]; then
      run touch "$HOME/.gitconfig"
    fi
  '';

  programs.git = {
    enable = true;
    # Tec puts its own git first on PATH on the work Mac.
    package = if profile == "work" then null else pkgs.git;

    settings = {
      user = {
        inherit (user) name email;
      };
      alias = {
        st = "status";
        b = "branch --show-current";
        c = "commit -m";
        a = "add";
        aa = "add -A";
        au = "add -u";
        last = "log -1 HEAD --stat";
        rv = "remote -v";
        d = "diff";
        dv = "difftool -t vimdiff -y";
        gl = "config --global -l";
        p = "push origin $(git rev-parse --abbrev-ref HEAD)";
        co = "checkout";
        nb = "checkout -b";
        dunk = "!git diff | dunk";
      };
      core = {
        excludesfile = "~/.gitignore";
        pager = "delta";
      };
      interactive.diffFilter = "delta --color-only --features=interactive";
      delta = {
        features = "side-by-side line-numbers decorations";
        syntax-theme = "Dracula";
        plus-style = "syntax '#003800'";
        minus-style = "syntax '#3f0001'";
        file-decoration-style = "none";
        hunk-header-decoration-style = "cyan box ul";
        pager = "less --mouse -R";
        decorations = {
          commit-decoration-style = "bold yellow box ul";
          file-style = "bold yellow ul";
        };
        line-numbers = {
          line-numbers-left-style = "cyan";
          line-numbers-right-style = "cyan";
          line-numbers-minus-style = 124;
          line-numbers-plus-style = 28;
        };
      };
      # `task setup` turns signing on in ~/.config/git/signing once a key exists.
      commit.gpgsign = false;
    };

    includes = [
      # This machine's signing key, written by `task setup`.
      { path = "~/.config/git/signing"; }
      # Conditional includes that switch some repos, such as work ones, to another identity.
      # They live in the private repo because they name the systems involved; git skips the
      # file when it is absent. It must stay last so it overrides the identity and the key.
      { path = "~/src/github.com/kalindudc/shell-private/git/gitconfig"; }
    ];
  };
}
