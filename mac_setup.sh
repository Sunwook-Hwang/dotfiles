#!/usr/bin/env bash
# Setup script for setting up a new macOS machine.

set -euo pipefail

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURDIR/source/dotfiles_options.sh"
parse_dotfiles_options setup "$@"
SOURCE="$CURDIR/source"
source "$SOURCE/claude_cli.sh"
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

function ensure_homebrew {
  # Check for Homebrew to be present, install if it's missing
  brew_path_setup

  if ! command -v brew >/dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew_path_setup
  fi
}

function update_setup {
  ensure_homebrew
  brew update
  brew upgrade --greedy
  brew doctor || true
  setup_claude_cli update
  if ! "$DOTFILES_EXCLUDE_VSCODE"; then
    bash "$CURDIR/vscode/export_extensions.sh" --update
  fi
  run_dotfiles_script install_dotfiles.sh
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
  setup_claude_cli
  if ! command -v "${CODEX_BIN:-codex}" >/dev/null 2>&1; then
    brew install --cask codex
  fi
}

function zsh_setup {
  echo "[*] zsh_setup"

  run_dotfiles_script clean_dotfiles.sh

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
  run_dotfiles_script install_dotfiles.sh

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

COMMAND="$DOTFILES_SETUP_TARGET"

if [[ "$COMMAND" == "" || "$COMMAND" == "base" ]]; then
  xcode_setup
  ensure_homebrew

  base_setup
  zsh_setup
  if ! "$DOTFILES_EXCLUDE_VSCODE"; then
    vscode_setup
  fi

  cask_setup
  font_setup

  neovide_setup
  bash "$CURDIR/install_agent_tools.sh"

elif [[ "$COMMAND" == "update" ]]; then
  update_setup
elif [[ "$COMMAND" == "link" ]]; then
  echo "*** LINK DOTFILES ***"
  run_dotfiles_script install_dotfiles.sh
elif [[ "$COMMAND" == "unlink" ]]; then
  echo "*** UNLINK DOTFILES ***"
  run_dotfiles_script clean_dotfiles.sh
else
  echo "Unknown setup target: $COMMAND" >&2
  echo "Usage: ${0##*/} [base|update|link|unlink]" >&2
  exit 1
fi
if command -v brew >/dev/null 2>&1; then
  brew cleanup --prune=0
fi
