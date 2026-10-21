#!/usr/bin/env bash

set -euo pipefail

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURDIR/source/dotfiles_options.sh"
parse_dotfiles_options stow "$@"
TARGET="${STOW_TARGET:-$HOME}"
STOW_ARGS=(--no-folding)

if [[ "${EUID:-$(id -u)}" -eq 0 && -z "${STOW_TARGET:-}" ]]; then
  echo "Do not run this script with sudo unless STOW_TARGET is set explicitly." >&2
  exit 1
fi

cd "$CURDIR"

echo "Unlinking dotfiles from $TARGET"

for folder in claude codex ghostty git herdr nvim neovide-terminal tmux zsh csh tools; do
  [[ -d "$folder" ]] || continue
  echo "Unlinking $folder"
  stow "${STOW_ARGS[@]}" -D -t "$TARGET" "$folder"
done

if ! "$DOTFILES_EXCLUDE_VSCODE"; then
  echo "VS Code settings copies and extensions are kept."
else
  echo "Skipping VS Code unlink (--exclude vscode)."
fi

echo "Done."
