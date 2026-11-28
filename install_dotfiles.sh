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
      # Stow owns only relative links; an absolute link to the same file still conflicts.
      [[ -L "$target_path" && "$target_path" -ef "$CURDIR/$path" && "$(readlink "$target_path")" != /* ]] && continue
      backup_path="$BACKUP_DIR/$relative"
      mkdir -p "$(dirname "$backup_path")"
      echo "Backing up existing $target_path -> $backup_path"
      mv "$target_path" "$backup_path"
    fi
  done < <(git ls-files --cached --others --exclude-standard "$folder")
}

# Back up whatever stow itself still reports as a conflict, such as files the
# checkout ignores or links that stow sees as foreign.
function backup_stow_conflicts {
  local folder="$1" relative backup_path
  { stow "${STOW_ARGS[@]}" -n -R -t "$TARGET" "$folder" 2>&1 || true; } | sed -n -E \
    -e 's/^  \* existing target is (not owned by stow|neither a link nor a directory): (.*)$/\2/p' \
    -e 's/^  \* existing target is stowed to a different package: (.*) => .*$/\1/p' \
    -e 's/^  \* cannot stow .* over existing (non-)?directory target (.*)$/\2/p' \
    -e 's/^  \* cannot stow .* over existing target (.*) since neither a link nor a directory.*$/\1/p' |
    while IFS= read -r relative; do
      [[ -e "$TARGET/$relative" || -L "$TARGET/$relative" ]] || continue
      backup_path="$BACKUP_DIR/$relative"
      mkdir -p "$(dirname "$backup_path")"
      echo "Backing up existing $TARGET/$relative -> $backup_path"
      mv "$TARGET/$relative" "$backup_path"
    done
}

# Older installs linked whole directories into the checkout, so agents wrote
# their own files there. Move those untracked files back to the target.
function move_untracked_out {
  local folder="$1" path relative target_path backup_path
  while IFS= read -r -d '' path; do
    path="${path%/}"
    relative="${path#"$folder"/}"
    target_path="$TARGET/$relative"
    if [[ -e "$target_path" || -L "$target_path" ]]; then
      backup_path="$BACKUP_DIR/$relative"
      mkdir -p "$(dirname "$backup_path")"
      echo "Backing up existing $target_path -> $backup_path"
      mv "$target_path" "$backup_path"
    fi
    mkdir -p "$(dirname "$target_path")"
    echo "Moving untracked $CURDIR/$path -> $target_path"
    mv "$path" "$target_path"
  done < <(git ls-files -z --others --directory "$folder")
}

for folder in antigravity claude codex ghostty git herdr nvim neovide-terminal rvim zsh csh tmux tools; do
  [[ -d "$folder" ]] || continue
  echo "Linking $folder"
  backup_conflicts "$folder"
  stow "${STOW_ARGS[@]}" -D -t "$TARGET" "$folder"
  move_untracked_out "$folder"
  backup_stow_conflicts "$folder"
  stow "${STOW_ARGS[@]}" -t "$TARGET" "$folder"
done

codex_dir="$TARGET/.codex"
if [[ "$TARGET" == "$HOME" ]]; then codex_dir="${CODEX_HOME:-$codex_dir}"; fi
if [[ -f "$codex_dir/config.local.toml" || -f "$codex_dir/.dotfiles-overlay.json" ]]; then
  python3 "$CURDIR/source/sync_codex_config.py" "$codex_dir"
fi

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
else
  echo "Skipping VS Code settings (--exclude vscode)."
fi

for app in nvim neovide-terminal; do
  if [[ ! "$TARGET/.config/$app/init.lua" -ef "$CURDIR/$app/.config/$app/init.lua" ]]; then
    echo "Neovim configuration was not linked correctly: $TARGET/.config/$app/init.lua" >&2
    exit 1
  fi
done

# Start rvi once so its first real launch with the linked config is warm.
# Any failure or a run past 10 s is ignored; the install has already succeeded.
function warm_rvi {
  local rvi_bin=${RVI_BIN:-} pid i
  if [[ -z "$rvi_bin" ]]; then
    rvi_bin=$(command -v rvi 2>/dev/null || ls -t "$TARGET"/.local/opt/*/*/rvi 2>/dev/null | head -n 1 || true)
  fi
  [[ -n "$rvi_bin" && -x "$rvi_bin" ]] || return 0
  # rvi prefers init.lua over init.scm; then there is no Steel image to warm.
  [[ ! -e "${XDG_CONFIG_HOME:-$TARGET/.config}/rvim/init.lua" ]] || return 0
  echo "Warming rvi: $rvi_bin"
  "$rvi_bin" --headless -i NONE '+qa!' </dev/null >/dev/null 2>&1 &
  pid=$!
  for ((i = 0; i < 100; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    kill -KILL "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}
[[ "$TARGET" != "$HOME" ]] || warm_rvi

# Herdr has no declarative plugin list: install missing plugins, then update all.
# `herdr plugin update` keeps the --ref recorded at install, so pinned plugins stay put.
HERDR_PLUGINS=(
  "persiyanov.reviewr persiyanov/herdr-reviewr"
  # Temporary until Herdr ships pane layout cycling: herdrdev/herdr discussions #1359.
  "herdr-layout-cycle amiramay/herdr-layout-cycle 39f95f30436893697f18e723d57ec2c44c506f62"
)
function install_herdr_plugins {
  command -v herdr >/dev/null 2>&1 || return 0
  local installed entry id repo ref
  installed="$(herdr plugin list 2>/dev/null || true)"
  for entry in "${HERDR_PLUGINS[@]}"; do
    read -r id repo ref <<<"$entry"
    [[ "$installed" == *"- $id "* ]] && continue
    echo "Installing Herdr plugin: $repo${ref:+ @ $ref}"
    herdr plugin install --yes "$repo" ${ref:+--ref "$ref"} ||
      echo "Warning: Herdr plugin $repo failed to install; continuing without it." >&2
  done
  echo "Updating Herdr plugins"
  herdr plugin update --yes ||
    echo "Warning: Herdr plugin update failed; continuing." >&2
}
[[ "$TARGET" != "$HOME" ]] || install_herdr_plugins

echo "Done."
