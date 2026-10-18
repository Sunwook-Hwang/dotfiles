#!/usr/bin/env bash
# Shared public options for setup, Stow installation and removal.

function dotfiles_usage {
  if [[ "$DOTFILES_OPTION_MODE" == setup ]]; then
    echo "Usage: ${0##*/} [base|update|link|unlink] [--exclude vscode]"
  else
    echo "Usage: ${0##*/} [--exclude vscode]"
  fi
}

function parse_dotfiles_options {
  DOTFILES_OPTION_MODE="$1"
  shift
  DOTFILES_EXCLUDE_VSCODE=false
  DOTFILES_SETUP_TARGET=""
  while (($#)); do
    case "$1" in
    --exclude)
      if [[ "${2:-}" != vscode ]]; then
        echo "--exclude requires: vscode" >&2
        dotfiles_usage >&2
        exit 1
      fi
      DOTFILES_EXCLUDE_VSCODE=true
      shift 2
      ;;
    -h | --help)
      dotfiles_usage
      exit 0
      ;;
    base | update | link | unlink)
      if [[ "$DOTFILES_OPTION_MODE" != setup || -n "$DOTFILES_SETUP_TARGET" ]]; then
        dotfiles_usage >&2
        exit 1
      fi
      DOTFILES_SETUP_TARGET="$1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      dotfiles_usage >&2
      exit 1
      ;;
    esac
  done
}

function run_dotfiles_script {
  if "$DOTFILES_EXCLUDE_VSCODE"; then
    bash "$CURDIR/$1" --exclude vscode
  else
    bash "$CURDIR/$1"
  fi
}
