# Checks the ~/.zshrc that Home Manager wrote, from an interactive zsh:
#   zsh -i -c 'source test/smoke/zshrc.zsh'
# CI runs it after a switch (.github/workflows/check.yml).

failures=0
fail() { print -u2 "✗ $*"; (( failures++ )); }

for tool in atuin delta direnv fd fzf git herdr jq kubectl lazygit nvim rg starship task zoxide; do
  case "$(whence -p $tool)" in
    /nix/store/*|*/.nix-profile/*|/etc/profiles/per-user/*|*/home-path/*) ;;
    *) fail "$tool should come from the Nix profile, got '$(whence -p $tool)'" ;;
  esac
done

[[ -d "$ZSH_PLUGIN_DIR/ohmyzsh/plugins/git" ]] || fail "ZSH_PLUGIN_DIR has no oh-my-zsh git plugin: $ZSH_PLUGIN_DIR"
(( $+functions[_evalcache] )) || fail "evalcache is not loaded"
(( $+functions[_zsh_autosuggest_start] )) || fail "zsh-autosuggestions is not loaded"
(( $+functions[_task] )) || autoload -Uz +X _task 2>/dev/null || fail "no completion for task"
(( $+functions[_todo] )) || autoload -Uz +X _todo 2>/dev/null || fail "no completion for todo"
[[ "$(alias gst)" == "gst='git status'" ]] || fail "the oh-my-zsh git aliases are missing"
[[ -n "$STARSHIP_SHELL" ]] || fail "starship is not initialised"
[[ -f "$HOME/.config/ghostty/config-os" ]] || fail "~/.config/ghostty/config-os is missing"
[[ "$(git -C "$HOME" config core.pager)" == delta ]] || fail "git does not read ~/.config/git/config"

(( failures == 0 )) && print "✓ zshrc smoke test passed"
exit $(( failures > 0 ))
