#!/usr/bin/env bash
# Shared native Claude Code installation for macOS and Linux setup.

function setup_claude_cli {
  export PATH="$HOME/.local/bin:$PATH"

  if command -v claude >/dev/null 2>&1; then
    # Native installs own this launcher; package managers update their own copies.
    if [[ "${1:-install}" == update && "$(command -v claude)" == "$HOME/.local/bin/claude" ]]; then
      claude update
    fi
  else
    local installer status=0
    installer="$(mktemp)"
    if curl -fsSL https://claude.ai/install.sh -o "$installer"; then
      bash "$installer" || status=$?
    else
      status=$?
    fi
    rm -f "$installer"
    if [[ "$status" -ne 0 ]]; then
      echo "Claude Code installation failed." >&2
      return "$status"
    fi
  fi

  if ! command -v claude >/dev/null 2>&1; then
    echo "Claude Code installer did not provide $HOME/.local/bin/claude." >&2
    return 1
  fi
  claude --version
}
