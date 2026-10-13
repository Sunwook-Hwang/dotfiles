#!/bin/sh
# Install the package-based Neovim profile and its bundled plugins.
set -eu

usage() {
  echo "Usage: sh update_pvi.sh [pvi.zip]"
  echo "Without a ZIP, download pvi.zip from the latest Dotfiles release."
  echo "Back up and replace only the nvim-pack configuration and vim.pack plugins."
}
if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  usage
  exit 0
fi
if [ "$#" -gt 1 ]; then
  usage >&2
  exit 1
fi
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
work=$(mktemp -d "$PWD/pvi-release.XXXXXX")
if [ -z "$archive" ]; then
  archive="$work/pvi.zip"
  curl -fL https://github.com/Sunwook-Hwang/dotfiles/releases/latest/download/pvi.zip -o "$archive"
fi
unzip -q "$archive" -d "$work"
bundle="$work/pvi"
source_config="$bundle/config/nvim-pack"
source_plugins="$bundle/data/nvim-pack/site/pack/core/opt"
if [ ! -f "$source_config/init.lua" ] || [ ! -d "$source_config/lua" ] ||
  [ ! -s "$source_config/nvim-pack-lock.json" ] || [ ! -s "$bundle/plugins.txt" ]; then
  echo "ZIP does not contain a complete pvi bundle (use pvi.zip, not Source code.zip)." >&2
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
mkdir -p "$config_home" "$plugin_parent"
config_home=$(cd "$config_home" && pwd -P)
plugin_parent=$(cd "$plugin_parent" && pwd -P)
config_target="$config_home/nvim-pack"
plugin_target="$plugin_parent/opt"
config_stage=
plugin_stage=
config_backup=
plugin_backup=
config_installed=0
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
    if [ "$config_installed" -eq 1 ]; then rm -rf "$config_target"; fi
    if [ -n "$config_backup" ] && { [ -e "$config_backup" ] || [ -L "$config_backup" ]; }; then
      mv "$config_backup" "$config_target" || echo "Restore configuration manually: $config_backup" >&2
    fi
  fi
  if [ -n "$config_stage" ]; then rm -rf "$config_stage"; fi
  if [ -n "$plugin_stage" ]; then rm -rf "$plugin_stage"; fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# Stage both directories before moving an existing installation or Stow link.
config_stage=$(mktemp -d "$config_home/.pvi-update.XXXXXX")
plugin_stage=$(mktemp -d "$plugin_parent/.pvi-update.XXXXXX")
cp -R "$source_config" "$config_stage/nvim-pack"
cp -R "$source_plugins" "$plugin_stage/opt"
if [ -e "$config_target" ] || [ -L "$config_target" ]; then
  config_backup=$(mktemp -d "$config_home/nvim-pack.backup.XXXXXX")
  rmdir "$config_backup"
  mv "$config_target" "$config_backup"
fi
if [ -e "$plugin_target" ] || [ -L "$plugin_target" ]; then
  plugin_backup=$(mktemp -d "$plugin_parent/opt.backup.XXXXXX")
  rmdir "$plugin_backup"
  mv "$plugin_target" "$plugin_backup"
fi
mv "$plugin_stage/opt" "$plugin_target"
plugins_installed=1
mv "$config_stage/nvim-pack" "$config_target"
config_installed=1
complete=1
echo "Installed pvi configuration: $config_target"
echo "Installed plugins: $plugin_target"
if [ -n "$config_backup" ]; then echo "Previous configuration: $config_backup"; fi
if [ -n "$plugin_backup" ]; then echo "Previous plugins: $plugin_backup"; fi
echo "Release files: $work"
echo "Mason tools, sessions, undo history and FLASH were left unchanged."
echo "Restart pvi, or run: env NVIM_APPNAME=nvim-pack nvim"
