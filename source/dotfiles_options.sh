#!/usr/bin/env bash
# Shared public options for setup, Stow installation and removal.

function dotfiles_usage {
  if [[ "$DOTFILES_OPTION_MODE" == setup ]]; then
    echo "Usage: ${0##*/} [base|update|link|unlink]"
  else
    echo "Usage: ${0##*/}"
  fi
}

function parse_dotfiles_options {
  DOTFILES_OPTION_MODE="$1"
  shift
  DOTFILES_SETUP_TARGET=""
  while (($#)); do
    case "$1" in
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
  bash "$CURDIR/$1"
}
