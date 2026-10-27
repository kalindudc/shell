# The only unfree packages this flake may install.
{ lib }:
pkg:
builtins.elem (lib.getName pkg) [
  "1password-cli"
]
