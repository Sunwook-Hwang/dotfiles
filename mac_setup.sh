#!/usr/bin/env bash
# Setup script for setting up a new macOS machine.

set -euo pipefail

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$CURDIR/source"
USERDIR="$HOME"

echo "Starting setup"

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Do not run this script with sudo. Homebrew and stow should run as your user." >&2
  exit 1
fi

function xcode_setup {
  if xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools already installed."
  else
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
  fi
}

function brew_path_setup {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

function brew_setup {
  # Check for Homebrew to be present, install if it's missing
  brew_path_setup

  if ! command -v brew >/dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew_path_setup
  else
    if [[ -z "${CI:-}" ]]; then
      brew update
      brew upgrade --greedy || true
      brew doctor || true
    fi
  fi
}

function font_setup {
  brew update
  echo "Installing fonts..."
  FONTS=(
    font-roboto-mono-nerd-font
  )
  echo "Installing cask fonts..."
  brew install --cask "${FONTS[@]}" --force
}

function cask_setup {
  brew update
  echo "Installing cask..."
  CASKS=(
    google-drive
    iterm2
    mactex
    slack
    spotify
  )
  if brew list --cask mactex-no-gui >/dev/null 2>&1; then
    echo "mactex-no-gui is installed; uninstalling it before installing mactex."
    brew uninstall --cask mactex-no-gui
  fi
  echo "Installing cask apps..."
  brew install --cask "${CASKS[@]}" --force
}

function base_setup {
  brew update
  PACKAGES=(
    bear
    bat
    bash-language-server
    black
    buf
    buildifier
    ccache
    clang-format
    cmake
    cmake-language-server
    curl
    fd
    fzf
    gh
    git
    herdr
    htop
    jq
    lazygit
    latexindent
    llvm
    lua-language-server
    neocmakelsp
    neovim
    ninja
    node
    pkg-config
    prettier
    pyright
    python3
    ripgrep
    ruff
    rust
    rust-analyzer
    shfmt
    stow
    stylua
    tailwindcss-language-server
    texlab
    tldr
    tmux
    tree
    ty
    typescript-language-server
    universal-ctags
    uv
    vscode-langservers-extracted
    wget
    yaml-language-server
  )
  echo "Installing packages..."
  brew install "${PACKAGES[@]}"
}

function zsh_setup {
  echo "[*] zsh_setup"

  source "$CURDIR/clean_dotfiles.sh"

  # prerequisite for zsh setup
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    RUNZSH=no CHSH=no sh "$SOURCE/ohmyzsh.sh" --skip-chsh
  fi

  PACKAGES=(
    autojump
  )

  echo "Installing packages..."
  brew install "${PACKAGES[@]}"

  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM/plugins"
  [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] ||
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] ||
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

  rm -f "$USERDIR/.zshrc"
}

function neovide_setup {
  brew list --versions neovide >/dev/null 2>&1 || brew install neovide
  brew list --versions dockutil >/dev/null 2>&1 || brew install dockutil
  brew list --cask font-roboto-mono-nerd-font >/dev/null 2>&1 ||
    brew install --cask font-roboto-mono-nerd-font
  bash "$CURDIR/install_dotfiles.sh"

  local launcher="$HOME/.local/bin/neovide-terminal-nvim"
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/neovide"
  local nvim_bin="$(brew --prefix)/bin/nvim"
  local app="$(brew --prefix neovide)/Neovide.app"
  local config_tmp launcher_toml home_toml
  mkdir -p "$HOME/.local/bin" "$config_dir" "$HOME/Applications"
  printf '#!/bin/bash\nexec env NVIM_APPNAME=neovide-terminal %q "$@"\n' "$nvim_bin" >"$launcher"
  chmod +x "$launcher"

  # Set the startup profile without discarding other Neovide preferences.
  launcher_toml="${launcher//\\/\\\\}"
  launcher_toml="${launcher_toml//\"/\\\"}"
  home_toml="${HOME//\\/\\\\}"
  home_toml="${home_toml//\"/\\\"}"
  config_tmp="$(mktemp "$config_dir/config.toml.XXXXXX")"
  printf 'neovim-bin = "%s"\nchdir = "%s"\n' "$launcher_toml" "$home_toml" >"$config_tmp"
  if [[ -f "$config_dir/config.toml" ]]; then
    awk '!/^[[:space:]]*(neovim-bin|chdir)[[:space:]]*=/' "$config_dir/config.toml" >>"$config_tmp"
  fi
  mv "$config_tmp" "$config_dir/config.toml"
  if [[ ! -e "$HOME/Applications/Neovide.app" || -L "$HOME/Applications/Neovide.app" ]]; then
    ln -sfn "$app" "$HOME/Applications/Neovide.app"
  fi
  dockutil --add "$HOME/Applications/Neovide.app" --replacing Neovide
  echo "Neovide is ready as a terminal: $HOME/Applications/Neovide.app"
}

function vscode_setup {
  echo "[*] vscode_setup"

  defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false
  defaults write com.microsoft.VSCodeInsiders ApplePressAndHoldEnabled -bool false
  defaults write com.visualstudio.code.oss ApplePressAndHoldEnabled -bool false
}

# ==================================================================
############ MAIN ############
# ------------------------------------------------------------------

COMMAND="${1:-}"

if [[ "$COMMAND" == "" || "$COMMAND" == "base" ]]; then
  xcode_setup
  brew_setup

  base_setup
  zsh_setup
  vscode_setup

  cask_setup
  font_setup

  neovide_setup

elif [[ "$COMMAND" == "link" ]]; then
  echo "*** LINK DOTFILES ***"
  source "$CURDIR/install_dotfiles.sh"
elif [[ "$COMMAND" == "unlink" ]]; then
  echo "*** UNLINK DOTFILES ***"
  source "$CURDIR/clean_dotfiles.sh"
else
  if declare -F "${COMMAND}_setup" >/dev/null; then
    if [[ "$COMMAND" != "brew" && "$COMMAND" != "xcode" ]]; then
      brew_setup
    fi
    "${COMMAND}_setup"
  else
    echo "Unknown setup target: $COMMAND" >&2
    exit 1
  fi
fi
if command -v brew >/dev/null 2>&1; then
  brew cleanup --prune=0
fi
