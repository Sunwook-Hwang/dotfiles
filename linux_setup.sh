#!/usr/bin/env bash
# Setup script for Linux machines.

set -euo pipefail

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$CURDIR/source"
USERDIR="$HOME"

echo "Starting Linux setup"

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Do not run this script with sudo. It uses sudo only for system package commands." >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required to install system packages. Install sudo first, then run this script as your normal user." >&2
  exit 1
fi

PKG_MANAGER=""

COMMON_PACKAGES=(
  autojump
  bash
  bat
  bear
  build_tools
  ca_certificates
  ccache
  clang
  clang_format
  clangd
  cmake
  curl
  ctags
  fd
  fzf
  gh
  gdb
  git
  gzip
  htop
  jq
  lazygit
  lldb
  node
  ninja
  npm
  pkg_config
  prettier
  python
  python_pip
  python_venv
  ripgrep
  rust
  stow
  stylua
  tar
  tldr
  tmux
  tree
  unzip
  valgrind
  vim
  wget
  wl_clipboard
  xclip
  zsh
)

function detect_package_manager {
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
  else
    echo "Unsupported Linux distribution: apt-get, dnf, yum, or pacman is required." >&2
    exit 1
  fi
}

function package_setup {
  detect_package_manager

  case "$PKG_MANAGER" in
  apt)
    sudo apt-get update
    ;;
  dnf)
    sudo dnf makecache
    ;;
  yum)
    sudo yum makecache
    ;;
  pacman)
    sudo pacman -Sy
    ;;
  esac
}

function pkg_install {
  local packages=("$@")

  case "$PKG_MANAGER" in
  apt)
    sudo apt-get install -y "${packages[@]}"
    ;;
  dnf)
    sudo dnf install -y "${packages[@]}"
    ;;
  yum)
    sudo yum install -y "${packages[@]}"
    ;;
  pacman)
    sudo pacman -S --needed --noconfirm "${packages[@]}"
    ;;
  esac
}

function pkg_install_if_available {
  local package

  for package in "$@"; do
    if package_exists "$package"; then
      pkg_install "$package"
    else
      echo "Skipping unavailable package: $package"
    fi
  done
}

function install_package_id {
  local package_id="$1"
  local package_name

  package_name="$(package_name_for "$package_id")"

  if [[ -z "$package_name" ]]; then
    echo "Skipping unsupported package: $package_id"
    return
  fi

  if package_exists "$package_name"; then
    pkg_install "$package_name"
  else
    echo "Skipping unavailable package: $package_name"
  fi
}

function package_name_for {
  local package_id="$1"

  case "$PKG_MANAGER:$package_id" in
  apt:autojump) echo "autojump" ;;
  apt:build_tools) echo "build-essential" ;;
  apt:ca_certificates) echo "ca-certificates" ;;
  apt:ctags) echo "universal-ctags" ;;
  apt:clang_format) echo "clang-format" ;;
  apt:fd) echo "fd-find" ;;
  apt:ninja) echo "ninja-build" ;;
  apt:node) echo "nodejs" ;;
  apt:pkg_config) echo "pkg-config" ;;
  apt:python) echo "python3" ;;
  apt:python_pip) echo "python3-pip" ;;
  apt:python_venv) echo "python3-venv" ;;
  apt:rust) echo "rustc" ;;
  apt:wl_clipboard) echo "wl-clipboard" ;;
  apt:*) echo "$package_id" ;;

  dnf:autojump | yum:autojump) echo "autojump-zsh" ;;
  dnf:build_tools | yum:build_tools) echo "@development-tools" ;;
  dnf:ca_certificates | yum:ca_certificates) echo "ca-certificates" ;;
  dnf:ctags | yum:ctags) echo "universal-ctags" ;;
  dnf:clang_format | yum:clang_format) echo "clang-tools-extra" ;;
  dnf:clangd | yum:clangd) echo "clang-tools-extra" ;;
  dnf:fd | yum:fd) echo "fd-find" ;;
  dnf:ninja | yum:ninja) echo "ninja-build" ;;
  dnf:node | yum:node) echo "nodejs" ;;
  dnf:pkg_config | yum:pkg_config) echo "pkgconf-pkg-config" ;;
  dnf:python | yum:python) echo "python3" ;;
  dnf:python_pip | yum:python_pip) echo "python3-pip" ;;
  dnf:python_venv | yum:python_venv) echo "" ;;
  dnf:rust | yum:rust) echo "rust" ;;
  dnf:wl_clipboard | yum:wl_clipboard) echo "wl-clipboard" ;;
  dnf:* | yum:*) echo "$package_id" ;;

  pacman:build_tools) echo "base-devel" ;;
  pacman:ca_certificates) echo "ca-certificates" ;;
  pacman:ctags) echo "universal-ctags" ;;
  pacman:fd) echo "fd" ;;
  pacman:gh) echo "github-cli" ;;
  pacman:clang_format) echo "clang" ;;
  pacman:clangd) echo "clang" ;;
  pacman:node) echo "nodejs" ;;
  pacman:pkg_config) echo "pkgconf" ;;
  pacman:python) echo "python" ;;
  pacman:python_pip) echo "python-pip" ;;
  pacman:python_venv) echo "" ;;
  pacman:wl_clipboard) echo "wl-clipboard" ;;
  pacman:*) echo "$package_id" ;;
  esac
}

function package_exists {
  local package="$1"

  if [[ "$package" == @* ]]; then
    return 0
  fi

  case "$PKG_MANAGER" in
  apt)
    apt-cache show "$package" >/dev/null 2>&1
    ;;
  dnf)
    dnf list --available "$package" >/dev/null 2>&1 || dnf list --installed "$package" >/dev/null 2>&1
    ;;
  yum)
    yum list available "$package" >/dev/null 2>&1 || yum list installed "$package" >/dev/null 2>&1
    ;;
  pacman)
    pacman -Si "$package" >/dev/null 2>&1 || pacman -Qi "$package" >/dev/null 2>&1
    ;;
  esac
}

function command_alias_setup {
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    sudo mkdir -p /usr/local/bin
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi

  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    sudo mkdir -p /usr/local/bin
    sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
  fi
}

function autojump_available {
  command -v autojump >/dev/null 2>&1 ||
    [[ -f /etc/profile.d/autojump.sh ]] ||
    [[ -f /usr/share/autojump/autojump.sh ]] ||
    [[ -f /usr/share/autojump/autojump.zsh ]] ||
    [[ -f /usr/local/etc/profile.d/autojump.sh ]] ||
    [[ -f /usr/local/share/autojump/autojump.sh ]] ||
    [[ -f /usr/local/share/autojump/autojump.zsh ]] ||
    [[ -f "$HOME/.autojump/etc/profile.d/autojump.sh" ]] ||
    [[ -f "$HOME/.autojump/etc/profile.d/autojump.zsh" ]]
}

function install_autojump_fallback {
  local python_cmd
  local tmpdir

  if autojump_available; then
    return
  fi

  echo "Installing autojump from source..."

  if command -v python3 >/dev/null 2>&1; then
    python_cmd="python3"
  elif command -v python >/dev/null 2>&1; then
    python_cmd="python"
  else
    echo "Cannot install autojump fallback: python is required." >&2
    return 1
  fi

  tmpdir="$(mktemp -d)"
  git clone --depth 1 https://github.com/wting/autojump "$tmpdir/autojump"
  (
    cd "$tmpdir/autojump"
    sudo "$python_cmd" install.py --destdir=/usr/local
  )
  rm -rf "$tmpdir"
}

function lazygit_asset_arch {
  case "$(uname -m)" in
  x86_64)
    echo "x86_64"
    ;;
  aarch64 | arm64)
    echo "arm64"
    ;;
  *)
    echo ""
    ;;
  esac
}

function install_lazygit_fallback {
  local arch
  local asset_url
  local release_json
  local tmpdir

  if command -v lazygit >/dev/null 2>&1; then
    return
  fi

  arch="$(lazygit_asset_arch)"
  if [[ -z "$arch" ]]; then
    echo "Cannot install lazygit fallback: unsupported architecture $(uname -m)." >&2
    return 1
  fi

  echo "Installing lazygit from GitHub release..."

  release_json="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest)"
  asset_url="$(printf '%s\n' "$release_json" | grep -Eo "https://[^\"]+lazygit_[^\"]+_Linux_${arch}\\.tar\\.gz" | head -n 1)"

  if [[ -z "$asset_url" ]]; then
    echo "Cannot find lazygit release asset for Linux_${arch}." >&2
    return 1
  fi

  tmpdir="$(mktemp -d)"
  curl -fsSL "$asset_url" -o "$tmpdir/lazygit.tar.gz"
  tar -C "$tmpdir" -xzf "$tmpdir/lazygit.tar.gz" lazygit
  sudo install -m 0755 "$tmpdir/lazygit" /usr/local/bin/lazygit
  rm -rf "$tmpdir"
}

function install_herdr_fallback {
  if command -v herdr >/dev/null 2>&1; then
    return
  fi

  echo "Installing Herdr..."
  curl -fsSL https://herdr.dev/install.sh | sh
}

function fallback_package_setup {
  install_autojump_fallback || echo "Warning: autojump fallback install failed; continuing without autojump." >&2
  install_herdr_fallback || echo "Warning: Herdr install failed; continuing without Herdr." >&2
  install_lazygit_fallback || echo "Warning: lazygit fallback install failed; continuing without lazygit." >&2
}

function nvim_binary_setup {
  local arch
  local package
  local url
  local archive

  arch="$(uname -m)"

  case "$arch" in
  x86_64)
    package="nvim-linux-x86_64"
    ;;
  aarch64 | arm64)
    package="nvim-linux-arm64"
    ;;
  *)
    echo "Unsupported architecture for Neovim prebuilt binary: $arch" >&2
    return 1
    ;;
  esac

  archive="/tmp/${package}.tar.gz"
  url="https://github.com/neovim/neovim/releases/latest/download/${package}.tar.gz"

  curl -L "$url" -o "$archive"
  sudo rm -rf "/opt/$package"
  sudo tar -C /opt -xzf "$archive"
  sudo ln -sf "/opt/$package/bin/nvim" /usr/local/bin/nvim
}

function base_setup {
  echo "[*] base_setup"

  package_setup
  install_base_packages
  fallback_package_setup
  nvim_binary_setup
  command_alias_setup
  locale_setup
  package_cleanup
}

function install_base_packages {
  local package_id

  for package_id in "${COMMON_PACKAGES[@]}"; do
    install_package_id "$package_id"
  done

  if [[ "$PKG_MANAGER" == "apt" ]]; then
    pkg_install_if_available locales software-properties-common
  fi
}

function locale_setup {
  case "$PKG_MANAGER" in
  apt)
    sudo locale-gen en_US.UTF-8 || true
    ;;
  *)
    true
    ;;
  esac
}

function package_cleanup {
  case "$PKG_MANAGER" in
  apt)
    sudo apt-get clean
    ;;
  dnf)
    sudo dnf clean all
    ;;
  yum)
    sudo yum clean all
    ;;
  pacman)
    true
    ;;
  esac
}

function zsh_setup {
  echo "[*] zsh_setup"

  source "$CURDIR/clean_dotfiles.sh"

  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    RUNZSH=no CHSH=no sh "$SOURCE/ohmyzsh.sh" --skip-chsh
  fi

  install_autojump_fallback || echo "Warning: autojump fallback install failed; continuing without autojump." >&2

  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM/plugins"
  [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] ||
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] ||
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

  rm -f "$USERDIR/.zshrc"

  if [[ "$(basename "${SHELL:-}")" != "zsh" ]]; then
    if ! chsh -s "$(command -v zsh)"; then
      echo "Warning: the login shell could not be changed. Contact your administrator or launch zsh manually." >&2
    fi
  fi
}

function tmux_setup {
  echo "[*] tmux_setup"

  source "$CURDIR/clean_dotfiles.sh"
  rm -f "$USERDIR/.tmux.conf"
}

function nvim_setup {
  echo "[*] nvim_setup"

  source "$CURDIR/clean_dotfiles.sh"
  rm -f "$USERDIR/.config/nvim/init.vim" "$USERDIR/.config/nvim/init.lua"
}

function core_setup {
  zsh_setup
  tmux_setup
  nvim_setup
}

# ==================================================================
############ MAIN ############
# ------------------------------------------------------------------

COMMAND="${1:-}"

if [[ "$COMMAND" == "" ]]; then
  base_setup
  core_setup
  source "$CURDIR/install_dotfiles.sh"
elif [[ "$COMMAND" == "base" ]]; then
  echo "*** BASE SETUP ***"
  base_setup
elif [[ "$COMMAND" == "link" ]]; then
  echo "*** LINK DOTFILES ***"
  source "$CURDIR/install_dotfiles.sh"
elif [[ "$COMMAND" == "unlink" ]]; then
  echo "*** UNLINK DOTFILES ***"
  source "$CURDIR/clean_dotfiles.sh"
else
  if declare -F "${COMMAND}_setup" >/dev/null; then
    if [[ "$COMMAND" != "package" ]]; then
      package_setup
    fi
    "${COMMAND}_setup"
  else
    echo "Unknown setup target: $COMMAND" >&2
    exit 1
  fi
fi

if [[ -n "$PKG_MANAGER" ]]; then
  package_cleanup
fi

# The setup runs in a child Bash process; changing the login shell does not
# switch the terminal that launched it. Start Zsh after the full setup completes.
if [[ "$COMMAND" == "" ]]; then
  if [[ -t 0 && -t 1 ]]; then
    exec zsh -l
  else
    echo "Setup complete. Run 'exec zsh -l' in your terminal to load the Zsh configuration."
  fi
fi
