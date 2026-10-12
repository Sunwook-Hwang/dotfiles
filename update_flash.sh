#!/bin/sh
# Install only the FLASH configuration from a GitHub release or a local ZIP.
set -eu

usage() {
  echo "Usage: sh update_flash.sh [release.zip]"
  echo "Without a ZIP, download the latest Dotfiles release."
  echo "Extract in the current directory and replace only the nvim configuration."
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
  echo "Downloading $tag..."
  curl -fL "$repo/archive/refs/tags/$tag.zip" -o "$archive"
fi
unzip -q "$archive" -d "$work"
set -- "$work"/*/nvim/.config/nvim
if [ "$#" -ne 1 ] || [ ! -f "$1/init.lua" ] || [ ! -d "$1/lua" ] || [ ! -d "$1/colors" ]; then
  echo "ZIP does not contain a complete FLASH configuration." >&2
  exit 1
fi
source_config=$1

config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
mkdir -p "$config_home"
config_home=$(cd "$config_home" && pwd -P)
target="$config_home/nvim"
stage=$(mktemp -d "$config_home/.flash-update.XXXXXX")
backup=
cleanup() {
  result=$?
  trap - EXIT HUP INT TERM
  if [ -n "$backup" ] && { [ -e "$backup" ] || [ -L "$backup" ]; } &&
    [ ! -e "$target" ] && [ ! -L "$target" ]; then
    mv "$backup" "$target" || echo "Restore the backup manually: $backup" >&2
  fi
  rm -rf "$stage"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# Stage the complete configuration before touching an existing directory or link.
cp -R "$source_config" "$stage/nvim"
if [ -e "$target" ] || [ -L "$target" ]; then
  backup=$(mktemp -d "$config_home/nvim.backup.XXXXXX")
  rmdir "$backup"
  mv "$target" "$backup"
  echo "Previous configuration: $backup"
fi
mv "$stage/nvim" "$target"
echo "Installed FLASH: $target"
echo "Release files: $work"
echo "Restart Neovim to load the updated configuration."
