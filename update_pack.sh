#!/bin/sh
# Install Vim or package-based Neovim plugins without replacing editor settings.
set -eu

usage() {
  echo "Usage: sh update_pack.sh vim|nvim [archive.zip]"
  echo "vim: install vimpack.zip (Vim LSP and completion plugins)."
  echo "nvim: install nvimpack.zip (pvi plugins and their lockfile)."
  echo "Without a ZIP, download the matching archive from the latest Dotfiles release."
}
if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  usage
  exit 0
fi
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage >&2
  exit 1
fi
editor=$1
case "$editor" in
vim | nvim) ;;
*) usage >&2; exit 1 ;;
esac
shift
command -v unzip >/dev/null 2>&1 || {
  echo "unzip is required." >&2
  exit 1
}
archive=${1:-}
if [ -n "$archive" ]; then
  case "$archive" in
  /*) ;;
  *) archive="$PWD/$archive" ;;
  esac
  [ -f "$archive" ] || {
    echo "ZIP not found: $archive" >&2
    exit 1
  }
else
  command -v curl >/dev/null 2>&1 || {
    echo "curl is required to download a release." >&2
    exit 1
  }
fi
work=$(mktemp -d "$PWD/pack-release.XXXXXX")
if [ -z "$archive" ]; then
  archive="$work/${editor}pack.zip"
  curl -fL "https://github.com/Sunwook-Hwang/dotfiles/releases/latest/download/${editor}pack.zip" -o "$archive"
fi
unzip -q "$archive" -d "$work"
if [ "$editor" = vim ]; then
  source_plugins="$work/vimpack/.vim/pack/vendor/opt"
  vim_plugins="vim-lsp asyncomplete.vim asyncomplete-lsp.vim"
  for plugin in $vim_plugins; do
    case "$plugin" in
    vim-lsp) script=lsp.vim ;;
    *) script=$plugin ;;
    esac
    if [ ! -d "$source_plugins/$plugin/.git" ] || [ ! -f "$source_plugins/$plugin/plugin/$script" ]; then
      echo "ZIP does not contain the Vim plugin bundle (use vimpack.zip)." >&2
      exit 1
    fi
  done
  plugin_parent="$HOME/.vim/pack/vendor/opt"
  mkdir -p "$plugin_parent"
  plugin_parent=$(cd "$plugin_parent" && pwd -P)
  plugin_stage=$(mktemp -d "$plugin_parent/.vimpack-stage.XXXXXX")
  plugin_backup=$(mktemp -d "$plugin_parent/.vimpack-backup.XXXXXX")
  complete=0
  has_backup=0
  cleanup_vim() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$complete" -eq 0 ] && [ -f "$plugin_stage/replaced" ]; then
      while IFS= read -r plugin; do
        rm -rf "$plugin_parent/$plugin"
        if [ -e "$plugin_backup/$plugin" ] || [ -L "$plugin_backup/$plugin" ]; then
          mv "$plugin_backup/$plugin" "$plugin_parent/$plugin" || echo "Restore plugin manually: $plugin_backup/$plugin" >&2
        fi
      done <"$plugin_stage/replaced"
    fi
    rm -rf "$plugin_stage"
    rmdir "$plugin_backup" 2>/dev/null || true
    exit "$result"
  }
  trap cleanup_vim EXIT
  trap 'exit 1' HUP INT TERM
  # Copy everything before replacing any installed plugin; keep unrelated plugins.
  mkdir "$plugin_stage/plugins"
  for plugin in $vim_plugins; do
    cp -R "$source_plugins/$plugin" "$plugin_stage/plugins/$plugin"
  done
  for plugin in $vim_plugins; do
    target="$plugin_parent/$plugin"
    if [ -e "$target" ] || [ -L "$target" ]; then
      mv "$target" "$plugin_backup/$plugin"
      has_backup=1
    fi
    echo "$plugin" >>"$plugin_stage/replaced"
    mv "$plugin_stage/plugins/$plugin" "$target"
  done
  complete=1
  echo "Installed Vim plugins: $plugin_parent"
  if [ "$has_backup" -eq 1 ]; then echo "Previous plugins: $plugin_backup"; fi
  echo "Release files: $work"
  echo "Restart Vim. Editor settings and unrelated plugins were left unchanged."
  exit 0
fi

bundle="$work/pack"
source_lock="$bundle/nvim-pack-lock.json"
source_plugins="$bundle/data/nvim-pack/site/pack/core/opt"
if [ ! -s "$source_lock" ] || [ ! -s "$bundle/plugins.txt" ]; then
  echo "ZIP does not contain a complete plugin bundle (use nvimpack.zip, not Source code.zip)." >&2
  exit 1
fi
while IFS= read -r plugin; do
  case "$plugin" in
  "" | . | .. | *[!A-Za-z0-9._-]*)
    echo "Invalid plugin name in bundle." >&2
    exit 1
    ;;
  esac
  [ -d "$source_plugins/$plugin/.git" ] || {
    echo "Bundled plugin is missing: $plugin" >&2
    exit 1
  }
done <"$bundle/plugins.txt"

config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
plugin_parent=${XDG_DATA_HOME:-"$HOME/.local/share"}/nvim-pack/site/pack/core
mkdir -p "$config_home/nvim-pack" "$plugin_parent"
config_home=$(cd "$config_home" && pwd -P)
plugin_parent=$(cd "$plugin_parent" && pwd -P)
lock_target="$config_home/nvim-pack/nvim-pack-lock.json"
plugin_target="$plugin_parent/opt"
lock_stage=
plugin_stage=
lock_backup=
plugin_backup=
lock_installed=0
plugins_installed=0
complete=0
cleanup() {
  result=$?
  trap - EXIT HUP INT TERM
  if [ "$complete" -eq 0 ]; then
    if [ "$plugins_installed" -eq 1 ]; then rm -rf "$plugin_target"; fi
    if [ -n "$plugin_backup" ] && { [ -e "$plugin_backup" ] || [ -L "$plugin_backup" ]; }; then
      mv "$plugin_backup" "$plugin_target" || echo "Restore plugins manually: $plugin_backup" >&2
    fi
    if [ "$lock_installed" -eq 1 ]; then rm -rf "$lock_target"; fi
    if [ -n "$lock_backup" ] && { [ -e "$lock_backup" ] || [ -L "$lock_backup" ]; }; then
      mv "$lock_backup" "$lock_target" || echo "Restore lockfile manually: $lock_backup" >&2
    fi
  fi
  if [ -n "$lock_stage" ]; then rm -rf "$lock_stage"; fi
  if [ -n "$plugin_stage" ]; then rm -rf "$plugin_stage"; fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# Stage plugins and lockfile before changing the installed versions.
lock_stage=$(mktemp -d "$config_home/nvim-pack/.pack-update.XXXXXX")
plugin_stage=$(mktemp -d "$plugin_parent/.pack-update.XXXXXX")
cp "$source_lock" "$lock_stage/nvim-pack-lock.json"
cp -R "$source_plugins" "$plugin_stage/opt"
# Build for the destination machine before replacing plugins or their lockfile.
# The bundle contains source, not a platform-specific library from the publisher.
fzf_source="$plugin_stage/opt/telescope-fzf-native.nvim"
if [ -d "$fzf_source" ]; then
  command -v make >/dev/null 2>&1 || {
    echo "fzf-native requires make and a C compiler (cc, GCC or Clang)." >&2
    exit 1
  }
  (cd "$fzf_source" && make)
fi
if [ -e "$lock_target" ] || [ -L "$lock_target" ]; then
  lock_backup=$(mktemp "$lock_target.backup.XXXXXX")
  rm "$lock_backup"
  mv "$lock_target" "$lock_backup"
fi
if [ -e "$plugin_target" ] || [ -L "$plugin_target" ]; then
  plugin_backup=$(mktemp -d "$plugin_parent/opt.backup.XXXXXX")
  rmdir "$plugin_backup"
  mv "$plugin_target" "$plugin_backup"
fi
mv "$plugin_stage/opt" "$plugin_target"
plugins_installed=1
mv "$lock_stage/nvim-pack-lock.json" "$lock_target"
lock_installed=1
complete=1
echo "Installed plugin lockfile: $lock_target"
echo "Installed plugins: $plugin_target"
if [ -n "$lock_backup" ]; then echo "Previous lockfile: $lock_backup"; fi
if [ -n "$plugin_backup" ]; then echo "Previous plugins: $plugin_backup"; fi
echo "Release files: $work"
echo "Editor settings, Mason tools, sessions and undo history were left unchanged."
echo "Restart pvi, or run: env NVIM_APPNAME=nvim-pack nvim"
