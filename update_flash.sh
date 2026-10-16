#!/bin/sh
# Back up and replace only the FLASH configuration from a release ZIP.
set -eu

usage() {
  echo "Usage: sh update_flash.sh [release.zip]"
  echo "Without a ZIP, download the latest Dotfiles release."
  echo "Replace only the nvim configuration; preserve installed tools and editor state."
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
repo=https://github.com/Sunwook-Hwang/dotfiles
archive=${1:-}
if [ -n "$archive" ]; then
  case "$archive" in /*) ;; *) archive="$PWD/$archive" ;; esac
  [ -f "$archive" ] || {
    echo "ZIP not found: $archive" >&2
    exit 1
  }
else
  command -v curl >/dev/null 2>&1 || {
    echo "curl is required for downloads." >&2
    exit 1
  }
fi
work=$(mktemp -d "$PWD/dotfiles-release.XXXXXX")
if [ -z "$archive" ]; then
  release=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$repo/releases/latest")
  tag=${release##*/}
  case "$tag" in
  "" | latest | *[!A-Za-z0-9._-]*)
    echo "Could not resolve the latest release." >&2
    exit 1
    ;;
  esac
  archive="$work/dotfiles-$tag.zip"
  curl -fL "$repo/archive/refs/tags/$tag.zip" -o "$archive"
fi
unzip -q "$archive" -d "$work"
set -- "$work"/*/nvim/.config/nvim/init.lua
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "ZIP does not contain FLASH (use Source code.zip)." >&2
  exit 1
fi
source_config=${1%/init.lua}
if [ ! -d "$source_config/lua" ] || [ ! -d "$source_config/colors" ]; then
  echo "ZIP does not contain a complete FLASH configuration." >&2
  exit 1
fi
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
mkdir -p "$config_home"
config_home=$(cd "$config_home" && pwd -P)
target="$config_home/nvim"
stage=$(mktemp -d "$config_home/.flash-update.XXXXXX")
backup=
installed=0
complete=0
cleanup() {
  result=$?
  trap - EXIT HUP INT TERM
  if [ "$complete" -eq 0 ]; then
    if [ "$installed" -eq 1 ]; then rm -rf "$target"; fi
    if [ -n "$backup" ] && { [ -e "$backup" ] || [ -L "$backup" ]; }; then
      mv "$backup" "$target" || echo "Restore configuration manually: $backup" >&2
    fi
  fi
  rm -rf "$stage"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
cp -R "$source_config" "$stage/nvim"
if [ -e "$target" ] || [ -L "$target" ]; then
  backup=$(mktemp -d "$config_home/nvim.backup.XXXXXX")
  rmdir "$backup"
  mv "$target" "$backup"
fi
mv "$stage/nvim" "$target"
installed=1
complete=1
echo "Installed FLASH: $target"
if [ -n "$backup" ]; then echo "Previous configuration: $backup"; fi
echo "Release files: $work"
echo "Installed tools, sessions and undo history were preserved. Restart Neovim."
