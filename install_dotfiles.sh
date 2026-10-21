#!/usr/bin/env bash

set -euo pipefail

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURDIR/source/dotfiles_options.sh"
parse_dotfiles_options stow "$@"
TARGET="${STOW_TARGET:-$HOME}"
BACKUP_DIR="${STOW_BACKUP_DIR:-$TARGET/.backup_dotfiles/$(date +%Y%m%d%H%M%S)}"
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
      if [[ -L "$target_path" || (-e "$target_path" && ! -d "$target_path") ]]; then
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

if ! "$DOTFILES_EXCLUDE_VSCODE"; then
# VS Code gets independent copies so runtime settings do not change the checkout.
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

function copy_vscode {
  local name destination backup="" stage
  mkdir -p "$VSCODE_USER_DIR"
  stage=$(mktemp -d "$VSCODE_USER_DIR/.dotfiles-vscode.XXXXXX")
  for name in settings.json keybindings.json snippets; do
    cp -R "$CURDIR/vscode/user/$name" "$stage/$name"
  done
  for name in settings.json keybindings.json snippets; do
    destination="$VSCODE_USER_DIR/$name"
    if [[ -e "$destination" || -L "$destination" ]]; then
      if [[ -z "$backup" ]]; then
        mkdir -p "$BACKUP_DIR"
        backup=$(mktemp -d "$BACKUP_DIR/vscode.XXXXXX")
      fi
      # Save independent contents even when migrating Stow's file/directory links.
      if [[ -e "$destination" ]]; then
        cp -RL "$destination" "$backup/$name"
      else
        cp -P "$destination" "$backup/$name"
      fi
    fi
  done
  for name in settings.json keybindings.json snippets; do
    rm -rf "$VSCODE_USER_DIR/$name"
    mv "$stage/$name" "$VSCODE_USER_DIR/$name"
  done
  rmdir "$stage"
  [[ -z "$backup" ]] || echo "VS Code settings backed up: $backup"
  echo "VS Code settings copied: $VSCODE_USER_DIR (settings.json, keybindings.json, snippets)"
}
copy_vscode

function install_vscode_extensions {
  local code_bin installed_extensions extension failed installed_count skipped_count
  code_bin=${CODE_BIN:-}
  if [ -z "$code_bin" ]; then
    if command -v code >/dev/null 2>&1; then
      code_bin=code
    elif [ -x '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' ]; then
      code_bin='/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
    elif [ -x "$TARGET/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]; then
      code_bin="$TARGET/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    else
      echo 'Settings copied. VS Code CLI not found; install VS Code and rerun to install extensions.' >&2
      return 0
    fi
  fi

  echo "VS Code extension list: $CURDIR/vscode/extensions.txt"

  # Query once instead of launching VS Code again for every installed extension.
  if ! installed_extensions=$("$code_bin" --list-extensions); then
    echo 'Failed to list installed VS Code extensions; extension installation stopped.' >&2
    return 1
  fi
  installed_extensions=$(printf '%s\n' "$installed_extensions" | tr '[:upper:]' '[:lower:]' | tr -d '\r')

  failed=0
  installed_count=0
  skipped_count=0
  while IFS= read -r extension || [ -n "$extension" ]; do
    case "$extension" in "" | \#*) continue ;; esac
    case "
$installed_extensions
" in
    *"
$extension
"*)
      skipped_count=$((skipped_count + 1))
      continue
      ;;
    esac
    if ! "$code_bin" --install-extension "$extension"; then
      echo "Failed to install extension: $extension" >&2
      failed=$((failed + 1))
    else
      installed_count=$((installed_count + 1))
    fi
  done <"$CURDIR/vscode/extensions.txt"
  echo "VS Code extensions: $installed_count installed, $skipped_count already installed (skipped), $failed failed"
  return "$((failed > 0))"
}
install_vscode_extensions
else
  echo "Skipping VS Code settings and extensions (--exclude vscode)."
fi

for app in nvim neovide-terminal; do
  if [[ ! "$TARGET/.config/$app/init.lua" -ef "$CURDIR/$app/.config/$app/init.lua" ]]; then
    echo "Neovim configuration was not linked correctly: $TARGET/.config/$app/init.lua" >&2
    exit 1
  fi
done

echo "Done."
