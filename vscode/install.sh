#!/bin/sh
# Link portable VS Code preferences and optionally install their extensions.
set -eu

usage() {
  cat <<'EOF'
Usage: ./vscode/install.sh [--skip-extensions | --unlink]

Default: back up existing settings, link this checkout, then install extensions.
--skip-extensions  Link settings without downloading extensions.
--unlink           Remove only links owned by this checkout; keep extensions.

Targets VS Code's Default profile on macOS and Linux.
VSCODE_USER_DIR overrides the target settings directory.
VSCODE_BACKUP_ROOT overrides the backup parent directory.
CODE_BIN selects the VS Code CLI executable.
EOF
}

mode=install
case "${1:-}" in
--skip-extensions) mode=link ;;
--unlink) mode=unlink ;;
-h | --help)
  usage
  exit 0
  ;;
"") ;;
*)
  usage >&2
  exit 1
  ;;
esac
if [ "$#" -gt 1 ]; then
  usage >&2
  exit 1
fi

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
target_home=${STOW_TARGET:-$HOME}
if [ -n "${VSCODE_USER_DIR:-}" ]; then
  user_dir=$VSCODE_USER_DIR
else
  case "$(uname -s)" in
  Darwin) user_dir="$target_home/Library/Application Support/Code/User" ;;
  Linux)
    if [ "$target_home" = "$HOME" ]; then
      user_dir="${XDG_CONFIG_HOME:-$target_home/.config}/Code/User"
    else
      user_dir="$target_home/.config/Code/User"
    fi
    ;;
  *)
    echo 'Unsupported OS; set VSCODE_USER_DIR explicitly.' >&2
    exit 1
    ;;
  esac
fi
backup_root=${VSCODE_BACKUP_ROOT:-$target_home/.dotfiles-backup}
backup_dir=

for name in settings.json keybindings.json snippets; do
  source_path="$source_dir/$name"
  target_path="$user_dir/$name"
  if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
    if [ "$mode" = unlink ]; then
      rm "$target_path"
      echo "Unlinked: $target_path"
    fi
    continue
  fi
  [ "$mode" != unlink ] || continue
  mkdir -p "$user_dir"
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    if [ -z "$backup_dir" ]; then
      mkdir -p "$backup_root"
      backup_dir=$(mktemp -d "$backup_root/vscode-$(date +%Y%m%d%H%M%S).XXXXXX")
    fi
    mv "$target_path" "$backup_dir/$name"
    echo "Backed up: $target_path -> $backup_dir/$name"
  fi
  ln -s "$source_path" "$target_path"
  echo "Linked: $target_path"
done

[ "$mode" = install ] || exit 0
code_bin=${CODE_BIN:-}
if [ -z "$code_bin" ]; then
  if command -v code >/dev/null 2>&1; then
    code_bin=code
  elif [ -x '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' ]; then
    code_bin='/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
  elif [ -x "$target_home/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]; then
    code_bin="$target_home/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  else
    echo 'Settings linked. VS Code CLI not found; install VS Code and rerun to install extensions.' >&2
    exit 0
  fi
fi

failed=0
while IFS= read -r extension || [ -n "$extension" ]; do
  case "$extension" in "" | \#*) continue ;; esac
  if ! "$code_bin" --install-extension "$extension"; then
    echo "Failed to install extension: $extension" >&2
    failed=1
  fi
done <"$source_dir/extensions.txt"
exit "$failed"
