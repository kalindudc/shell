# Ghostty renders fonts smaller on macOS (CoreText) than on Linux (FreeType) at the same
# size. The linked ghostty config loads this file with `config-file = ?config-os`.
{ pkgs, ... }:
{
  home.file.".config/ghostty/config-os".text = ''
    font-size = ${if pkgs.stdenv.hostPlatform.isDarwin then "13" else "11"}
  '';
}
