#!/bin/sh
# Install Vim, FLASH and package-based Neovim configurations from a release ZIP.
set -eu

usage() {
  echo "Usage: sh update_vims.sh [release.zip]"
  echo "Without a ZIP, download the latest Dotfiles release."
  echo "Back up and replace .vimrc, nvim and nvim-pack configurations; preserve plugins."
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
set -- "$work"/*/vim/.vimrc
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "ZIP does not contain vim/.vimrc (use Source code.zip)." >&2
  exit 1
fi
source_root=${1%/vim/.vimrc}
for profile in nvim nvim-pack; do
  source_config="$source_root/$profile/.config/$profile"
  if [ ! -f "$source_config/init.lua" ] || [ ! -d "$source_config/lua" ]; then
    echo "ZIP does not contain a complete $profile configuration." >&2
    exit 1
  fi
done
[ -d "$source_root/nvim/.config/nvim/colors" ] || {
  echo "ZIP does not contain FLASH colors." >&2
  exit 1
}

config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
mkdir -p "$config_home"
config_home=$(cd "$config_home" && pwd -P)
vim_stage=
vim_lsp_stage=
config_stage=
complete=0
select_profile() {
  case "$1" in
  vimrc)
    target="$HOME/.vimrc"
    source_config="$source_root/vim/.vimrc"
    stage=$vim_stage
    ;;
  vim-lsp)
    target="$HOME/.vim/lsp.vim"
    source_config="$source_root/vim/.vim/lsp.vim"
    stage=$vim_lsp_stage
    ;;
  *)
    target="$config_home/$1"
    source_config="$source_root/$1/.config/$1"
    stage=${config_stage:+$config_stage/$1}
    ;;
  esac
}
cleanup() {
  result=$?
  trap - EXIT HUP INT TERM
  for profile in nvim-pack nvim vim-lsp vimrc; do
    select_profile "$profile"
    [ -n "$stage" ] && [ -d "$stage" ] || continue
    if [ "$complete" -eq 0 ]; then
      if [ -f "$stage/installing" ]; then rm -rf "$target"; fi
      if [ -e "$stage/previous" ] || [ -L "$stage/previous" ]; then
        if ! mv "$stage/previous" "$target"; then
          echo "Restore the backup manually: $stage/previous" >&2
          result=1
          continue
        fi
      fi
      rm -rf "$stage"
    else
      rm -f "$stage/installing"
      if [ -e "$stage/previous" ] || [ -L "$stage/previous" ]; then
        echo "Previous $profile: $stage/previous"
      else
        rmdir "$stage"
      fi
    fi
  done
  if [ -n "$config_stage" ]; then rmdir "$config_stage" 2>/dev/null || true; fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

vim_stage=$(mktemp -d "$HOME/.vimrc.backup.XXXXXX")
if [ -f "$source_root/vim/.vim/lsp.vim" ]; then
  mkdir -p "$HOME/.vim"
  vim_lsp_stage=$(mktemp -d "$HOME/.vim/lsp.vim.backup.XXXXXX")
fi
config_stage=$(mktemp -d "$config_home/vims.backup.XXXXXX")
# Prepare replacements before moving any installed file or Stow link.
for profile in vimrc vim-lsp nvim nvim-pack; do
  select_profile "$profile"
  [ -n "$stage" ] || continue
  mkdir -p "$stage"
  cp -R "$source_config" "$stage/new"
  if [ "$profile" = nvim-pack ] && [ -f "$target/nvim-pack-lock.json" ]; then
    cp "$target/nvim-pack-lock.json" "$stage/new/nvim-pack-lock.json"
  fi
done
for profile in vimrc vim-lsp nvim nvim-pack; do
  select_profile "$profile"
  [ -n "$stage" ] || continue
  if [ -e "$target" ] || [ -L "$target" ]; then
    mv "$target" "$stage/previous"
  fi
  : >"$stage/installing"
  mv "$stage/new" "$target"
done
complete=1
echo "Installed Vim: $HOME/.vimrc"
if [ -n "$vim_lsp_stage" ]; then echo "Installed optional Vim LSP configuration: $HOME/.vim/lsp.vim"; fi
echo "Installed FLASH: $config_home/nvim"
echo "Installed package-based Neovim: $config_home/nvim-pack"
echo "Release files: $work"
echo "Plugins and their lockfile, Mason tools, sessions and undo history were preserved."
echo "Restart the editors. Run update_pack.sh separately to install/update pvi plugins."
