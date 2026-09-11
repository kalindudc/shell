#!/usr/bin/env bash
# clip.sh — copy stdin to the system clipboard, portably.
#
# Usage:  cat brief.md | clip.sh
#         clip.sh < brief.md
#
# Picks the first available backend: pbcopy (macOS), wl-copy (Wayland),
# xclip / xsel (X11), clip.exe (WSL / Windows). Prints a one-line
# confirmation with the byte count, or fails loudly (exit 1) with the
# manual fallback if no clipboard tool exists.

set -uo pipefail

tmp=$(mktemp -t handover-clip.XXXXXX) || { echo "clip.sh: cannot create tempfile" >&2; exit 1; }
trap 'rm -f "$tmp"' EXIT
cat > "$tmp"
bytes=$(wc -c < "$tmp" | tr -d ' ')

copy() { command -v "$1" >/dev/null 2>&1; }

if copy pbcopy; then
  pbcopy < "$tmp" && { echo "clip.sh: copied ${bytes} bytes to clipboard (pbcopy)"; exit 0; }
elif copy wl-copy; then
  wl-copy < "$tmp" && { echo "clip.sh: copied ${bytes} bytes to clipboard (wl-copy)"; exit 0; }
elif copy xclip; then
  xclip -selection clipboard < "$tmp" && { echo "clip.sh: copied ${bytes} bytes to clipboard (xclip)"; exit 0; }
elif copy xsel; then
  xsel --clipboard --input < "$tmp" && { echo "clip.sh: copied ${bytes} bytes to clipboard (xsel)"; exit 0; }
elif copy clip.exe; then
  clip.exe < "$tmp" && { echo "clip.sh: copied ${bytes} bytes to clipboard (clip.exe)"; exit 0; }
fi

echo "clip.sh: no clipboard tool found (tried pbcopy, wl-copy, xclip, xsel, clip.exe)." >&2
echo "clip.sh: the brief was NOT copied. It is preserved at: $tmp" >&2
trap - EXIT   # keep the file so the user can copy it manually
exit 1
