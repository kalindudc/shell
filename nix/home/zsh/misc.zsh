if [[ "$(uname)" == "Linux" ]]; then
  # Use xclip to copy/paste to clipboard
  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
fi
