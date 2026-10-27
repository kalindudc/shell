# Links the files in home/ into $HOME, pointing at the checkout so edits apply at once.
# A file added to home/ needs `git add` and `task switch`, because a flake only sees
# tracked files.
{ config, lib, ... }:
let
  repo = "${config.home.homeDirectory}/src/github.com/kalindudc/shell";

  # Tools also write into these directories, so they stay real directories in $HOME and
  # their children are linked one by one. Any other directory is linked as a whole, so
  # files written into it (node_modules, SKILL_NOTES.md, private packs) land in the
  # checkout, where .gitignore covers them.
  realDirs = [
    ".agents"
    ".agents/skills"
    ".config"
    ".config/ghostty"
    ".config/herdr"
    ".gnupg"
    ".pi"
    ".pi/agent"
    ".pi/agent/extensions"
    "bin"
  ];

  # The nvim config is a git submodule, which the flake source leaves out.
  submodules = [ ".config/nvim" ];

  ignored = [ "README.md" ];

  entries =
    dir: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        let
          path = prefix + name;
        in
        if type == "directory" && builtins.elem path realDirs then
          entries (dir + "/${name}") "${path}/"
        else if builtins.elem path ignored then
          [ ]
        else
          [ path ]
      ) (builtins.readDir dir)
    );

  links = lib.unique (entries ../../home "" ++ submodules);
in
{
  home.file = lib.genAttrs links (path: {
    source = config.lib.file.mkOutOfStoreSymlink "${repo}/home/${path}";
  });
}
