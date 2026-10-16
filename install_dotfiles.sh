#!/usr/bin/env bash

set -euo pipefail

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${STOW_TARGET:-$HOME}"
BACKUP_DIR="${STOW_BACKUP_DIR:-$TARGET/.dotfiles-backup/$(date +%Y%m%d%H%M%S)}"
STOW_ARGS=(--no-folding)

if [[ "${EUID:-$(id -u)}" -eq 0 && -z "${STOW_TARGET:-}" ]]; then
  echo "Do not run this script with sudo unless STOW_TARGET is set explicitly." >&2
  exit 1
fi

cd "$CURDIR"

echo "Stowing dotfiles into $TARGET"

function backup_conflicts {
  local folder="$1"
  local path relative target_path backup_path remaining prefix

  while IFS= read -r path; do
    [[ -e "$path" || -L "$path" ]] || continue
    relative="${path#"$folder"/}"
    remaining="$relative"
    prefix=""
    # Back up foreign directory links themselves, never files through those links.
    while [[ "$remaining" == */* ]]; do
      prefix="${prefix:+$prefix/}${remaining%%/*}"
      remaining="${remaining#*/}"
      target_path="$TARGET/$prefix"
      if [[ -L "$target_path" || ( -e "$target_path" && ! -d "$target_path" ) ]]; then
        [[ -L "$target_path" && "$target_path" -ef "$CURDIR/$folder/$prefix" ]] && continue 2
        backup_path="$BACKUP_DIR/$prefix"
        mkdir -p "$(dirname "$backup_path")"
        echo "Backing up existing $target_path -> $backup_path"
        mv "$target_path" "$backup_path"
        continue 2
      fi
    done
    target_path="$TARGET/$relative"

    if [[ -e "$target_path" || -L "$target_path" ]]; then
      [[ -L "$target_path" && "$target_path" -ef "$CURDIR/$path" ]] && continue
      backup_path="$BACKUP_DIR/$relative"
      mkdir -p "$(dirname "$backup_path")"
      echo "Backing up existing $target_path -> $backup_path"
      mv "$target_path" "$backup_path"
    fi
  done < <(git ls-files --cached --others --exclude-standard "$folder")
}

for folder in claude codex ghostty git herdr nvim neovide-terminal zsh csh tmux tools; do
  [[ -d "$folder" ]] || continue
  echo "Linking $folder"
  backup_conflicts "$folder"
  stow "${STOW_ARGS[@]}" -D -t "$TARGET" "$folder"
  stow "${STOW_ARGS[@]}" -t "$TARGET" "$folder"
done

for app in nvim neovide-terminal; do
  if [[ ! "$TARGET/.config/$app/init.lua" -ef "$CURDIR/$app/.config/$app/init.lua" ]]; then
    echo "Neovim configuration was not linked correctly: $TARGET/.config/$app/init.lua" >&2
    exit 1
  fi
done

echo "Done."
