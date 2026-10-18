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
# VS Code uses the same Stow package on both OSes, with a different target.
if [[ -z "${VSCODE_USER_DIR:-}" ]]; then
  case "$(uname -s)" in
  Darwin) VSCODE_USER_DIR="$TARGET/Library/Application Support/Code/User" ;;
  Linux)
    if [[ "$TARGET" == "$HOME" ]]; then
      VSCODE_USER_DIR="${XDG_CONFIG_HOME:-$TARGET/.config}/Code/User"
    else
      VSCODE_USER_DIR="$TARGET/.config/Code/User"
    fi
    ;;
  *)
    echo "Unsupported VS Code OS; set VSCODE_USER_DIR explicitly." >&2
    exit 1
    ;;
  esac
fi

if [[ -d "$VSCODE_USER_DIR" ]]; then
  stow "${STOW_ARGS[@]}" -d "$CURDIR/vscode" -D -t "$VSCODE_USER_DIR" user
  echo "VS Code settings unlinked: $VSCODE_USER_DIR"
fi

else
  echo "Skipping VS Code unlink (--exclude vscode)."
fi

echo "Done."
